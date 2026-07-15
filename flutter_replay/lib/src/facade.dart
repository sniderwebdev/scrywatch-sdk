import 'package:flutter/widgets.dart';

import 'mask.dart';
import 'recorder.dart';

/// The public entrypoint for the ScryWatch session-replay SDK.
///
/// Typical usage:
///
/// ```dart
/// Future<void> main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await ScrywatchReplay.init(apiKey: 'YOUR_API_KEY');
///   runApp(const MyApp());
/// }
///
/// class MyApp extends StatelessWidget {
///   const MyApp({super.key});
///
///   @override
///   Widget build(BuildContext context) {
///     return MaterialApp(
///       // `builder` inserts the capture boundary BELOW MaterialApp's own
///       // Directionality/MediaQuery, wrapping the Navigator — so pushed
///       // routes are captured too.
///       builder: ScrywatchReplay.wrap,
///       home: const HomeScreen(),
///     );
///   }
/// }
/// ```
///
/// Nothing is captured until consent is granted:
///
/// ```dart
/// ScrywatchReplay.setConsent(true);
/// ```
///
/// [ScrywatchReplay] is a single process-wide facade — this preview release
/// supports one recorder/capture boundary per app, matching how
/// [MaskRegistry] is scoped.
class ScrywatchReplay {
  ScrywatchReplay._();

  static ReplayRecorder? _recorder;
  static final GlobalKey _boundaryKey =
      GlobalKey(debugLabel: 'scrywatch_replay_boundary');

  /// True once [init] has completed and the recorder is ready.
  static bool get isInitialized => _recorder != null;

  /// The current replay session id, or the empty string before [init]
  /// completes. Useful for support/debugging — paste it into the ScryWatch
  /// dashboard's Replay view to jump straight to this session.
  static String get sessionId => _recorder?.sessionId ?? '';

  /// Initializes session replay: creates the recorder, generates and
  /// persists a session id, and fetches this project's remote mask policy —
  /// falling back to the safe blocklist-mode default on any failure (see
  /// the fail-safe contract documented on the internal
  /// `ReplayRecorder._fetchAndApplyPolicy`).
  ///
  /// Call this once, early in `main()`, before [wrap] is used. [init] alone
  /// does not start capturing anything — call [setConsent] with `true` to
  /// begin recording.
  static Future<void> init({
    required String apiKey,
    String endpoint = 'https://api.scrywatch.com',
  }) async {
    final ReplayRecorder recorder = ReplayRecorder(
      endpoint: endpoint,
      apiKey: apiKey,
      boundaryKey: _boundaryKey,
    );
    _recorder = recorder;
    await recorder.start();
  }

  /// Grants or revokes recording consent.
  ///
  /// Nothing is captured, encoded, or uploaded until this is called with
  /// `true`. Calling it with `false` stops capture immediately. Safe to
  /// call before [init] completes, or repeatedly — it's a no-op until a
  /// recorder exists.
  static void setConsent(bool granted) {
    final ReplayRecorder? recorder = _recorder;
    if (recorder == null) return;
    recorder.setConsent(granted);
    if (granted) {
      recorder.resume();
    } else {
      recorder.stop();
    }
  }

  /// Stops recording outright. Equivalent to `setConsent(false)`. Safe to
  /// call at any time, including before [init].
  static void stop() {
    _recorder?.setConsent(false);
    _recorder?.stop();
  }

  /// Wraps [child] in the capture boundary. Pass this directly as
  /// `MaterialApp.builder` (or `CupertinoApp.builder`/`WidgetsApp.builder`)
  /// so it sits BELOW the app's `Directionality`/`MediaQuery` and wraps the
  /// `Navigator` — so pushed routes are captured too:
  ///
  /// ```dart
  /// MaterialApp(
  ///   builder: ScrywatchReplay.wrap,
  ///   home: const HomeScreen(),
  /// )
  /// ```
  ///
  /// The live screen is never altered or blacked out — masking is applied
  /// to the captured bitmap only, after capture. Safe to use before [init]
  /// completes: frames are simply dropped by the recorder until it's ready.
  static Widget wrap(BuildContext context, Widget? child) {
    return maskedRoot(
      boundaryKey: _boundaryKey,
      child: child ?? const SizedBox.shrink(),
    );
  }
}
