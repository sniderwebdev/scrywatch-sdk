// flutter/lib/log_client.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

enum LogLevel { error, warn, info, debug }

enum LogType { crash, session, navigation, apiCall, custom }

class LogEvent {
  final int timestamp;
  final String level;
  final String type;
  final String message;
  final String? userId;
  final String? sessionId;
  final String? environment;
  final String? service;
  final String? deviceType;
  final Map<String, dynamic>? metadata;

  LogEvent({
    required this.timestamp,
    required this.level,
    required this.type,
    required this.message,
    this.userId,
    this.sessionId,
    this.environment,
    this.service,
    this.deviceType,
    this.metadata,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp,
    'level': level,
    'type': type,
    'message': message,
    if (userId != null) 'user_id': userId,
    if (sessionId != null) 'session_id': sessionId,
    if (environment != null) 'environment': environment,
    if (service != null) 'service': service,
    if (deviceType != null) 'device_type': deviceType,
    if (metadata != null) 'metadata': metadata,
  };
}

class LogClient with WidgetsBindingObserver {
  static const String _deviceIdPrefsKey = 'scrywatch_device_id';

  final String endpoint;
  final String apiKey;
  final String? environment;
  final String? service;
  final String deviceType;
  final int maxBufferSize;
  final Duration flushInterval;
  final int maxRetries;
  final http.Client _httpClient;

  final List<LogEvent> _buffer = [];
  Timer? _timer;
  String? _sessionId;
  String? _userId;
  int _retryCount = 0;
  String? _deviceId;
  late final Future<void> _deviceIdReady;

  static String _detectDeviceType() {
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  static String _generateUuid() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    // Set version (4) and variant (RFC 4122) bits.
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).toList();
    return '${hex.sublist(0, 4).join()}-${hex.sublist(4, 6).join()}-'
        '${hex.sublist(6, 8).join()}-${hex.sublist(8, 10).join()}-'
        '${hex.sublist(10, 16).join()}';
  }

  LogClient({
    required this.endpoint,
    required this.apiKey,
    this.environment,
    this.service,
    String? deviceType,
    this.maxBufferSize = 50,
    this.flushInterval = const Duration(seconds: 10),
    this.maxRetries = 3,
    http.Client? httpClient,
  }) : deviceType = deviceType ?? _detectDeviceType(),
       _httpClient = httpClient ?? http.Client() {
    _timer = Timer.periodic(flushInterval, (_) => flush());
    WidgetsBinding.instance.addObserver(this);
    _deviceIdReady = _initDeviceId();
  }

  /// Loads the persisted anonymous device id from shared_preferences,
  /// generating and persisting a new one on first use. Falls back to an
  /// in-memory id (not persisted) if shared_preferences is unavailable —
  /// never throws.
  Future<void> _initDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var id = prefs.getString(_deviceIdPrefsKey);
      if (id == null || id.isEmpty) {
        id = _generateUuid();
        await prefs.setString(_deviceIdPrefsKey, id);
      }
      _deviceId = id;
    } catch (_) {
      _deviceId ??= _generateUuid();
    }
  }

  /// The persisted anonymous device id sent with every ingest request.
  /// Resolves once the id has been loaded/generated.
  Future<String> getDeviceId() async {
    await _deviceIdReady;
    return _deviceId ??= _generateUuid();
  }

  void setUserId(String userId) => _userId = userId;

  /// Identifies the current user: tags subsequent events with [userId] (same
  /// mechanism as [setUserId]) and upserts [traits] (e.g. email/name)
  /// server-side via `POST {endpoint}/api/identify`. Never throws — network
  /// or HTTP failures are caught and swallowed so a bad connection never
  /// surfaces an error to the host app.
  Future<void> identify(String userId, {Map<String, dynamic>? traits}) async {
    _userId = userId;
    try {
      await _httpClient
          .post(
            Uri.parse('$endpoint/api/identify'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode({
              'user_id': userId,
              if (traits != null) 'traits': traits,
            }),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // Swallow — identify must never throw to the caller.
    }
  }

  void startSession() {
    _sessionId = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    _addEvent(LogLevel.info, LogType.session, 'Session started');
  }

  void endSession() {
    _addEvent(LogLevel.info, LogType.session, 'Session ended');
    flush();
    _sessionId = null;
  }

  void log(LogLevel level, String message, {Map<String, dynamic>? metadata}) {
    _addEvent(level, LogType.custom, message, metadata: metadata);
  }

  void logError(Object error, StackTrace? stackTrace) {
    _addEvent(LogLevel.error, LogType.crash, error.toString(), metadata: {
      'stack_trace': stackTrace?.toString(),
    });
  }

  void logNavigation(String screen) {
    _addEvent(LogLevel.info, LogType.navigation, 'Navigated to $screen', metadata: {
      'screen': screen,
    });
  }

  void logApiCall(String method, String url, int statusCode, int durationMs) {
    final level = statusCode >= 400 ? LogLevel.error : LogLevel.info;
    _addEvent(level, LogType.apiCall, '$method $url -> $statusCode', metadata: {
      'method': method,
      'url': url,
      'status_code': statusCode,
      'duration_ms': durationMs,
    });
  }

  void _addEvent(LogLevel level, LogType type, String message, {Map<String, dynamic>? metadata}) {
    _buffer.add(LogEvent(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      level: level.name,
      type: type == LogType.apiCall ? 'api_call' : type.name,
      message: message,
      userId: _userId,
      sessionId: _sessionId,
      environment: environment,
      service: service,
      deviceType: deviceType,
      metadata: metadata,
    ));

    if (_buffer.length >= maxBufferSize) {
      flush();
    }
  }

  Future<void> flush() async {
    if (_buffer.isEmpty) return;

    final events = List<LogEvent>.from(_buffer);
    _buffer.clear();

    // Ensure the device id has been loaded/generated before the first send;
    // this resolves near-instantly on every call after the first.
    await _deviceIdReady;

    try {
      final response = await _httpClient.post(
        Uri.parse('$endpoint/api/ingest'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'events': events.map((e) => e.toJson()).toList(),
          if (_deviceId != null) 'device_id': _deviceId,
        }),
      );

      if (response.statusCode != 202) {
        _buffer.insertAll(0, events);
        _retryCount++;
        if (_retryCount >= maxRetries) {
          _buffer.removeRange(0, events.length.clamp(0, _buffer.length));
          _retryCount = 0;
        }
      } else {
        _retryCount = 0;
      }
    } catch (_) {
      _buffer.insertAll(0, events);
      _retryCount++;
      if (_retryCount >= maxRetries) {
        _buffer.removeRange(0, events.length.clamp(0, _buffer.length));
        _retryCount = 0;
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      flush();
    }
  }

  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    flush();
  }
}
