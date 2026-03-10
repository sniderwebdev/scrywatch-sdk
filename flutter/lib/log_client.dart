// flutter/lib/log_client.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

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
  final String endpoint;
  final String apiKey;
  final String? environment;
  final String? service;
  final String deviceType;
  final int maxBufferSize;
  final Duration flushInterval;
  final int maxRetries;

  final List<LogEvent> _buffer = [];
  Timer? _timer;
  String? _sessionId;
  String? _userId;
  int _retryCount = 0;

  static String _detectDeviceType() {
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
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
  }) : deviceType = deviceType ?? _detectDeviceType() {
    _timer = Timer.periodic(flushInterval, (_) => flush());
    WidgetsBinding.instance.addObserver(this);
  }

  void setUserId(String userId) => _userId = userId;

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

    try {
      final response = await http.post(
        Uri.parse('$endpoint/api/ingest'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'events': events.map((e) => e.toJson()).toList(),
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
