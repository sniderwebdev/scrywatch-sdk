# scrywatch_replay (Flutter SDK)

Session-replay SDK for [ScryWatch](https://scrywatch.com): record-by-default capture with opt-in, remote-policy-driven masking (and a strict deny-by-default mode) for Flutter apps.

> **Preview (0.4.0).** The public API in this package may change before a stable 1.0 release. Masking behavior is the gate we hold ourselves to most strictly — see [Masking model](#masking-model) below.

## Install

In `pubspec.yaml`:

```yaml
dependencies:
  scrywatch_replay: ^0.4.0
```

```bash
flutter pub get
```

## Quick start

```dart
import 'package:flutter/material.dart';
import 'package:scrywatch_replay/scrywatch_replay.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Creates the recorder, starts a fresh session for this app launch, and
  // fetches this project's remote mask policy. Nothing is captured yet.
  await ScrywatchReplay.init(apiKey: 'YOUR_API_KEY');

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // `builder` inserts the capture boundary BELOW MaterialApp's own
      // Directionality/MediaQuery and wraps the Navigator — so pushed
      // routes are captured too. The live screen is never altered; masking
      // is applied to the captured bitmap only, after capture.
      builder: ScrywatchReplay.wrap,
      home: const HomeScreen(),
    );
  }
}
```

Grant consent to start recording — nothing is captured, encoded, or uploaded before this call:

```dart
ScrywatchReplay.setConsent(true);
```

Revoke consent or stop recording outright at any time:

```dart
ScrywatchReplay.setConsent(false);
// or
ScrywatchReplay.stop();
```

See [`example/example.dart`](example/example.dart) for a complete runnable example.

## Identity

Every recorder carries an anonymous **`device_id`** — a random UUID generated
on first use and persisted via `shared_preferences` under
`scrywatch_device_id` (falling back to an in-memory id if
`shared_preferences` is unavailable — this never throws). It's the same
storage key used by the `scrywatch` logging SDK, so an app that uses both
SDKs shares a single device id across them. It's included as a top-level
`device_id` field in every segment upload's `x-replay-meta`, giving the
dashboard's Replay view cross-session continuity for anonymous users with
zero app code. It can take a tick or two after [`init`](#quick-start) for
`device_id` to be loaded (it's read from `shared_preferences`
asynchronously), so the very first segment of a session may not carry it —
every segment after that will.

When you know who's signed in, call `setUser` so the ScryWatch dashboard's
User Card can show who a replay session belongs to:

```dart
ScrywatchReplay.setUser('user_123'); // on sign-in
ScrywatchReplay.setUser(null);       // on sign-out
```

This tags subsequent segment uploads' `x-replay-meta` with `user_id:
'user_123'` until changed again. It's not persisted across restarts — call
it again (e.g. from wherever your app already knows who's signed in) after
every [`init`](#quick-start).

## Masking model

Every captured frame is redacted **after** capture, as a pass over the bitmap — the live screen on the user's device is never blacked out; only the pixels that leave the device are masked. This is the same approach used by Sentry/PostHog session replay.

Three widgets control what's eligible to show:

| Widget | Behavior |
|---|---|
| `ScrywatchTag('name', child: ...)` | Attaches an opaque, developer-chosen tag to a subtree. Whether a tagged region is masked is decided by the **remote mask policy** (configurable from the ScryWatch dashboard) via a `tag` rule — so you can start/stop masking a tagged region without an app release. |
| `ScrywatchMask(child: ...)` | Force-masks a subtree. Always occluded, in every mode, and can never be revealed — even inside a `ScrywatchReveal`. |
| `ScrywatchReveal(child: ...)` | Marks a subtree as eligible to show through the mask. Only matters in **strict** mode (see below); in **blocklist** mode it's a no-op. |

### The always-on floor

Regardless of tags, mode, or the remote policy, one thing is **always** masked and can never be revealed:

- Any `TextField`/`EditableText` with `obscureText: true` (password fields) — a secret a user types must never land in a stored frame.

Everything else records by default and is **opt-in** to mask via config rules or in-code widgets (see below) — including PII text and WebViews/native surfaces, which are **no longer masked automatically**:

- **PII text** (email, Luhn-valid card/PAN, SSN, phone) → add a `textPattern: email | card | ssn | phone` rule. Scanned from `Text`, `Text.rich`, `EditableText`, and `RichText`.
- **WebViews / native surfaces** (camera/video previews, platform views) → add a `widgetType: webview` or `video` rule, or wrap them in `ScrywatchMask`. Note these can't be captured meaningfully anyway (their pixels come from outside Flutter's render tree).

### Modes

The remote policy (fetched at `ScrywatchReplay.init()`, configurable in the ScryWatch dashboard's masking editor) sets one of two modes:

- **blocklist** (default) — records everything except the always-on floor (password fields) and anything matched by a rule (`tag`, `widgetType`, or `textPattern`). Record-everything-by-default; you opt into masking. Best fidelity/adoption.
- **strict** — deny-by-default: everything is masked except `ScrywatchReveal`-wrapped subtrees. The floor still wins — an obscured field inside a `ScrywatchReveal` is masked regardless. For HIPAA/PCI-grade projects.

### Fail-safe behavior

If the remote policy fetch fails (network error, timeout, malformed response) the SDK keeps its current policy — which is the safe blocklist-mode default on first run — and never falls back to something less strict. If a hard-masked element's on-screen position can't be resolved for a given frame (mid-relayout, just-mounted, etc.), the **entire frame** is occluded for that tick rather than risking an under-masked region shipping in the clear.

## Links

- [Session replay guide](https://scrywatch.com/guides/24-session-replay-overview)
- Dashboard masking editor — configure the remote policy without an app release (see your ScryWatch project settings)

## Dependencies

This package depends on [`package:http`](https://pub.dev/packages/http) (policy fetch + frame upload) and [`package:shared_preferences`](https://pub.dev/packages/shared_preferences) (persisting the anonymous `device_id`; session ids are per-launch and not persisted). No other dependencies.

## License

MIT
