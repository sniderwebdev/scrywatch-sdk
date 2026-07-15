/// ScryWatch session-replay SDK for Flutter.
///
/// Deny-by-default masking with an always-on PII floor, a remote-policy
/// -driven blocklist/strict mode, and post-capture bitmap redaction — the
/// live screen is never blacked out; only the pixels that leave the device
/// are.
///
/// Example:
/// ```dart
/// Future<void> main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await ScrywatchReplay.init(apiKey: 'YOUR_API_KEY');
///   runApp(const MyApp());
/// }
///
/// MaterialApp(
///   builder: ScrywatchReplay.wrap,
///   home: const HomeScreen(),
/// );
///
/// ScrywatchReplay.setConsent(true); // nothing is captured before this
/// ```
///
/// Tag, force-mask, or explicitly reveal content with [ScrywatchTag],
/// [ScrywatchMask], and [ScrywatchReveal]. See the package README for the
/// full masking model.
library scrywatch_replay;

export 'src/facade.dart' show ScrywatchReplay;
export 'src/mask.dart' show ScrywatchTag, ScrywatchMask, ScrywatchReveal;
