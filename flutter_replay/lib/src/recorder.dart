import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'mask.dart';

/// Bound on how long the startup policy fetch is allowed to block [start].
/// Keeps a slow/unreachable backend from ever meaningfully delaying app
/// startup — the safe default policy is already active before this fires.
const Duration _kPolicyFetchTimeout = Duration(seconds: 5);

/// Bound on how long a single frame upload is allowed to hang. Keeps a
/// slow/unreachable backend from piling up in-flight requests behind the
/// once-per-second capture timer.
const Duration _kUploadTimeout = Duration(seconds: 10);

/// Cap on how many distinct tags are reported per upload (see
/// [ReplayRecorder._seenTags]) — bounds the `x-replay-meta` header size
/// regardless of how many distinct [ScrywatchTag] strings an app defines.
const int _kMaxReportedTags = 50;

class ReplayRecorder with WidgetsBindingObserver {
  ReplayRecorder({
    required this.endpoint,
    required this.apiKey,
    required this.boundaryKey,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();
  final String endpoint;
  final String apiKey;
  final GlobalKey boundaryKey;

  /// SharedPreferences key for the persisted anonymous device id. This EXACT
  /// key is shared with the `scrywatch` (logging) SDK's `LogClient` — an app
  /// that uses both SDKs gets a single, consistent device id across them.
  static const String _deviceIdPrefsKey = 'scrywatch_device_id';

  /// Injectable for tests, so the policy-fetch and upload paths can be
  /// exercised against a `package:http/testing.dart` `MockClient` instead of
  /// the real network. Defaults to a real [http.Client] in production.
  final http.Client _httpClient;

  bool _consent = false;
  int _seq = 0;
  String _sessionId = '';
  Timer? _timer;

  /// Whether the [WidgetsBindingObserver] is currently registered — tracked
  /// so we register/unregister at most once and never leak the observer.
  bool _observing = false;

  /// True while capture is intended to be active (consent granted and
  /// [resume] has been called) — including while the timer is paused
  /// because the app is backgrounded. Used by [didChangeAppLifecycleState]
  /// to decide whether to restart the timer on resume.
  bool _capturing = false;

  /// The current replay session id — paste this into the ScryWatch
  /// dashboard's Replay view to watch this session back. Empty until
  /// [start] has run.
  String get sessionId => _sessionId;

  /// The persisted anonymous device id, or `null` until [start] has loaded
  /// (or generated) it. Included in `x-replay-meta` once available — see
  /// the loading-race note on [_tick].
  String? _deviceId;

  /// The current user id set via [setUser], or `null` when signed out /
  /// unknown. Not persisted — the host app is expected to call [setUser]
  /// again after every [start].
  String? _userId;

  int totalBytes = 0; // instrumentation
  final List<int> frameEncodeMs = []; // instrumentation
  int droppedFrames = 0; // instrumentation
  DateTime? _recordingStartedAt;
  // Bumped after every capture attempt so the metrics readout rebuilds only
  // when there's new data — avoids a free-running timer (which would break
  // widget-test pumpAndSettle).
  final ValueNotifier<int> metricsRevision = ValueNotifier<int>(0);

  Future<void> start() async {
    final prefs = await SharedPreferences.getInstance();
    _sessionId = prefs.getString('replay_session_id') ??
        (DateTime.now().microsecondsSinceEpoch.toRadixString(36));
    await prefs.setString('replay_session_id', _sessionId);
    debugPrint('[scrywatch_replay] session id: $_sessionId  '
        '(paste into the dashboard Replay view)');
    await _loadDeviceId(prefs);
    metricsRevision.value++; // surface the session id in the readout

    await _fetchAndApplyPolicy();
  }

  /// Loads the persisted anonymous device id from [prefs] under
  /// [_deviceIdPrefsKey], generating and persisting a new one on first use.
  /// Falls back to an in-memory id (not persisted) if reading/writing prefs
  /// throws — never lets a device-id failure crash [start]. Runs as part of
  /// [start], so [_deviceId] is populated promptly at init; it can still
  /// race a [resume] fired before [start] completes, same as [_sessionId]
  /// (see the guard in [_tick]).
  Future<void> _loadDeviceId(SharedPreferences prefs) async {
    try {
      String? id = prefs.getString(_deviceIdPrefsKey);
      if (id == null || id.isEmpty) {
        id = _generateUuid();
        await prefs.setString(_deviceIdPrefsKey, id);
      }
      _deviceId = id;
    } catch (e) {
      _deviceId ??= _generateUuid();
      debugPrint('[scrywatch_replay] device id load failed, using an '
          'in-memory id: $e');
    }
  }

  /// Generates a random RFC-4122-ish v4 UUID. Mirrors the logging SDK's
  /// `LogClient._generateUuid` so both device ids look the same shape.
  static String _generateUuid() {
    final Random rand = Random.secure();
    final List<int> bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    // Set version (4) and variant (RFC 4122) bits.
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final List<String> hex =
        bytes.map((int b) => b.toRadixString(16).padLeft(2, '0')).toList();
    return '${hex.sublist(0, 4).join()}-${hex.sublist(4, 6).join()}-'
        '${hex.sublist(6, 8).join()}-${hex.sublist(8, 10).join()}-'
        '${hex.sublist(10, 16).join()}';
  }

  /// Sets (or clears, with `null`) the current user id. Included as
  /// `user_id` in subsequent segment uploads' `x-replay-meta` until changed
  /// again. Not persisted — call this again after every [start] (typically
  /// from the same place your app already knows who's signed in). Call it
  /// on sign-in with the user's id, and with `null` on sign-out.
  void setUser(String? userId) => _userId = userId;

  /// Rotates to a brand-new session id, discarding the old one.
  ///
  /// Call this on sign-in / user change so a newly-signed-in user's frames
  /// can never be appended to a session that started under a different
  /// (possibly different-user) identity. Resets the frame sequence counter
  /// so the new session's frames are numbered from zero.
  Future<void> rotateSession() async {
    final String newSessionId =
        DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('replay_session_id', newSessionId);
    _sessionId = newSessionId;
    _seq = 0;
    debugPrint('[scrywatch_replay] session id rotated: $_sessionId');
    metricsRevision.value++;
  }

  /// Clears the current session entirely, leaving no active session id.
  ///
  /// Call this on sign-out so no further frames — including any captured
  /// before the next [start]/[rotateSession] — can be attributed to the
  /// signed-out user's session. [_tick] refuses to upload while the
  /// session id is empty (see the empty-session guard there).
  Future<void> clearSession() async {
    _sessionId = '';
    _seq = 0;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('replay_session_id');
    debugPrint('[scrywatch_replay] session cleared');
    metricsRevision.value++;
  }

  /// Fetches this project's remote mask policy and applies it via
  /// [MaskRegistry.setPolicy].
  ///
  /// SECURITY-CRITICAL fail-safe contract: masking must never end up
  /// WEAKER as a result of calling this. On ANY failure — network error,
  /// timeout, a non-200 response, or a body that isn't the expected JSON
  /// shape — this leaves [MaskRegistry.instance]'s current policy exactly
  /// as it was (the built-in blocklist-mode default on first run, or
  /// whatever a prior successful fetch already applied) and returns
  /// normally. The always-on floor (PII text, `obscureText`, platform
  /// surfaces — see mask.dart) applies regardless of policy or fetch
  /// outcome. Bounded by [_kPolicyFetchTimeout] so an unreachable backend
  /// can't hang app startup. Never throws.
  Future<void> _fetchAndApplyPolicy() async {
    try {
      final http.Response response = await _httpClient
          .get(
            Uri.parse('$endpoint/api/replay/policy'),
            headers: <String, String>{'Authorization': 'Bearer $apiKey'},
          )
          .timeout(_kPolicyFetchTimeout);
      if (response.statusCode != 200) {
        debugPrint(
          '[scrywatch_replay] mask policy fetch returned '
          '${response.statusCode}, keeping current policy',
        );
        return;
      }
      final Object? decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        debugPrint('[scrywatch_replay] mask policy response was not a JSON '
            'object, keeping current policy');
        return;
      }
      final MaskPolicy policy = MaskPolicy.fromJson(decoded);
      MaskRegistry.instance.setPolicy(policy);
      debugPrint(
        '[scrywatch_replay] applied mask policy v${policy.version} '
        '(mode: ${policy.mode.name}, ${policy.rules.length} rule(s))',
      );
    } catch (e) {
      // Network error, timeout, malformed JSON, unexpected shape, etc. —
      // never let a policy-fetch failure crash startup or weaken masking;
      // MaskRegistry keeps whatever policy it already had.
      debugPrint('[scrywatch_replay] mask policy fetch failed, keeping '
          'current policy: $e');
    }
  }

  void setConsent(bool v) => _consent = v;

  void resume() {
    _recordingStartedAt ??= DateTime.now();
    _capturing = true;
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void stop() {
    _capturing = false;
    _timer?.cancel();
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
  }

  /// Pauses capture while the app is backgrounded and resumes it when the
  /// app comes back to the foreground — never captures/uploads frames of a
  /// backgrounded app, and never leaves a timer running with no visible UI
  /// to sample.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _timer?.cancel();
        _timer = null;
      case AppLifecycleState.resumed:
        if (_consent && _capturing && _timer == null) {
          _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  /// Test-only seam that drives exactly one capture/upload attempt without
  /// waiting on the real once-per-second [Timer.periodic] in [resume] —
  /// lets tests exercise the upload fail-safe and empty-session guard
  /// deterministically. Not for production use.
  @visibleForTesting
  Future<void> debugTick() => _tick();

  Future<void> _tick() async {
    if (!_consent) return; // consent gate: capture nothing
    // Guards against the empty-session-id race: `resume()` may start the
    // timer before the async `start()` (which sets `_sessionId`) completes,
    // or after `clearSession()` has emptied it. Never POST a frame with no
    // session id to attribute it to.
    if (_sessionId.isEmpty) return;
    final sw = Stopwatch()..start();
    final Uint8List? png = await _captureMaskedPng();
    if (png == null) {
      droppedFrames++; // fail-safe: dropped an uncertain frame
      metricsRevision.value++;
      return;
    }
    sw.stop();
    frameEncodeMs.add(sw.elapsedMilliseconds);
    totalBytes += png.length;
    final seq = _seq++;
    final Map<String, Object?> meta = <String, Object?>{
      'session_id': _sessionId,
      'seq': seq,
      'start_ts': DateTime.now().millisecondsSinceEpoch,
      'end_ts': DateTime.now().millisecondsSinceEpoch,
      'frame_count': 1,
      'platform': 'flutter',
    };
    // `_deviceId` may still be null on the very first tick if `resume()` won
    // the race against the async `start()` (same race documented on
    // `_sessionId`) — we deliberately don't await it here so a slow/absent
    // SharedPreferences never delays capture. It's loaded promptly by
    // `start()`, so every subsequent segment carries it.
    if (_deviceId != null) meta['device_id'] = _deviceId;
    if (_userId != null) meta['user_id'] = _userId;
    final List<Map<String, String>> tags = _seenTags();
    if (tags.isNotEmpty) meta['tags'] = tags;
    await _uploadFrame(meta, png);
    metricsRevision.value++;
  }

  /// Uploads a single captured (already-masked) frame.
  ///
  /// Fail-safe contract: this must never let a network error, timeout, or
  /// any other exception escape — [_tick] runs on an unawaited
  /// `Timer.periodic`, so an uncaught throw here would hit the root zone.
  /// In host apps that route `PlatformDispatcher.onError` to a crash
  /// reporter, that would flood fatal reports at the capture cadence (up to
  /// 1/sec) every time the backend is briefly unreachable. On any failure
  /// we simply count the frame as dropped and move on — mirrors the
  /// fail-safe treatment in [_fetchAndApplyPolicy].
  Future<void> _uploadFrame(Map<String, Object?> meta, Uint8List png) async {
    try {
      await _httpClient
          .post(
            Uri.parse('$endpoint/api/replay'),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'x-replay-meta': jsonEncode(meta),
              'content-type': 'application/octet-stream',
            },
            body: png,
          )
          .timeout(_kUploadTimeout);
    } catch (e) {
      droppedFrames++; // fail-safe: never let an upload failure crash/escape
      debugPrint('[scrywatch_replay] frame upload failed, dropping frame: $e');
    }
  }

  /// The distinct tag strings currently registered via [ScrywatchTag] (see
  /// [MaskRegistry.taggedKeys]), shaped for `x-replay-meta.tags` so the
  /// worker can record what tags this project actually uses (tag
  /// telemetry) and the dashboard can offer them as a `tag`-rule pick-list.
  /// Capped at [_kMaxReportedTags] so an app with a runaway number of
  /// distinct tags can't bloat the upload header; this is purely reporting,
  /// it has no effect on what gets masked.
  List<Map<String, String>> _seenTags() {
    return MaskRegistry.instance.taggedKeys.keys
        .take(_kMaxReportedTags)
        .map((String tag) => <String, String>{'tag': tag, 'kind': 'tag'})
        .toList(growable: false);
  }

  // `boundaryKey` wraps the RAW app (see `maskedRoot()` in mask.dart — no
  // visible overlay). So we capture the raw frame, then redact it as a
  // POST-CAPTURE pass on the bitmap (`maskImage`) before encode/upload. The
  // live screen is never masked; only the pixels that leave the device are.
  //
  // Fail-safe at every step: if the boundary isn't mounted/laid out, or the
  // capture/mask/encode throws, we drop the frame rather than risk sending an
  // un-redacted one. `maskImage` itself also fails closed (fully-masked frame)
  // if rect resolution goes wrong — so we never under-mask.
  Future<Uint8List?> _captureMaskedPng() async {
    final ctx = boundaryKey.currentContext;
    if (ctx == null) return null; // fail-safe
    final boundary = ctx.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null || !boundary.attached || !boundary.hasSize) {
      return null; // fail-safe
    }
    const double pixelRatio = 1.0;
    // Resolve mask geometry synchronously from the currently laid-out tree,
    // BEFORE any await — so we never touch the BuildContext across an async
    // gap, and the geometry matches the frame we're about to capture. `scale`
    // is the capture pixelRatio (logical rects -> device pixels).
    final MaskGeometry geometry = computeMaskGeometry(ctx, boundary);
    ui.Image? raw;
    ui.Image? masked;
    try {
      raw = await boundary.toImage(pixelRatio: pixelRatio);
      masked = await maskImage(raw, geometry, scale: pixelRatio);
      final bytes = await masked.toByteData(format: ui.ImageByteFormat.png);
      return bytes?.buffer.asUint8List();
    } catch (_) {
      return null; // fail-safe: drop rather than risk an unmasked frame
    } finally {
      raw?.dispose();
      masked?.dispose();
    }
  }

  int get framesSent => _seq;

  /// Live measurement metrics, useful for an app's own on-device debug
  /// readout. Values mix int/double; keyed for a compact display + a
  /// copyable summary line.
  Map<String, Object> metrics() {
    final DateTime? started = _recordingStartedAt;
    final double elapsedSec = started == null
        ? 0
        : DateTime.now().difference(started).inMilliseconds / 1000.0;
    final double kbPerMin =
        elapsedSec > 0 ? (totalBytes / 1024.0) / (elapsedSec / 60.0) : 0;
    final List<int> sorted = List<int>.from(frameEncodeMs)..sort();
    final double avgMs = sorted.isEmpty
        ? 0
        : sorted.reduce((int a, int b) => a + b) / sorted.length;
    final int p95Ms =
        sorted.isEmpty ? 0 : sorted[((sorted.length - 1) * 0.95).floor()];
    return <String, Object>{
      'framesSent': _seq,
      'droppedFrames': droppedFrames,
      'totalKB': double.parse((totalBytes / 1024).toStringAsFixed(1)),
      'elapsedSec': double.parse(elapsedSec.toStringAsFixed(0)),
      'kbPerMin': double.parse(kbPerMin.toStringAsFixed(1)),
      'avgFrameMs': double.parse(avgMs.toStringAsFixed(1)),
      'p95FrameMs': p95Ms,
    };
  }

  /// One-line human-readable summary for the console / "copy metrics".
  String metricsSummary() {
    final Map<String, Object> m = metrics();
    return 'scrywatch_replay metrics — frames=${m['framesSent']} dropped=${m['droppedFrames']} '
        'total=${m['totalKB']}KB elapsed=${m['elapsedSec']}s rate=${m['kbPerMin']}KB/min '
        'avgEncode=${m['avgFrameMs']}ms p95Encode=${m['p95FrameMs']}ms';
  }
}
