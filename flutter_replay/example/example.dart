import 'package:flutter/material.dart';
import 'package:scrywatch_replay/scrywatch_replay.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Creates the recorder, generates/persists a session id, and fetches the
  // project's remote mask policy. Capture doesn't start until consent is
  // granted below.
  await ScrywatchReplay.init(apiKey: 'YOUR_API_KEY');

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ScryWatch Replay Example',
      // `builder` inserts the capture boundary BELOW MaterialApp's own
      // Directionality/MediaQuery and wraps the Navigator, so pushed
      // routes are captured too. The live screen is never altered —
      // masking only applies to the captured bitmap.
      builder: ScrywatchReplay.wrap,
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _recording = false;

  void _grantConsentAndRecord() {
    // Nothing is captured, encoded, or uploaded before this call.
    ScrywatchReplay.setConsent(true);
    setState(() => _recording = true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ScryWatch Replay — Example')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              'Email addresses, card numbers, SSNs, phone numbers, and '
              'obscureText fields are masked automatically by the '
              'always-on PII floor — no tagging required.',
            ),
            const SizedBox(height: 16),
            const TextField(
              decoration: InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 12),
            const TextField(
              obscureText: true,
              decoration: InputDecoration(labelText: 'Password'),
            ),
            const SizedBox(height: 16),
            // ScrywatchTag lets a dashboard rule mask this region later
            // without an app release, even though it isn't PII on its own.
            const ScrywatchTag(
              'internal-notes',
              child: Text('Personal notes: prefers morning runs.'),
            ),
            const SizedBox(height: 12),
            // ScrywatchMask force-masks this region unconditionally, even
            // in strict mode and even if a policy ever tried to reveal it.
            const ScrywatchMask(
              child: Text('Always redacted, no matter the policy.'),
            ),
            const SizedBox(height: 12),
            // ScrywatchReveal is only relevant in strict mode (deny by
            // default); in blocklist mode it's a no-op.
            const ScrywatchReveal(
              child: Text('Marketing copy — safe to show in strict mode.'),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _recording ? null : _grantConsentAndRecord,
              child: Text(_recording ? 'Recording…' : 'Grant consent & record'),
            ),
          ],
        ),
      ),
    );
  }
}
