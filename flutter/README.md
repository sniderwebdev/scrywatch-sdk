# scrywatch (Flutter SDK)

Official Dart/Flutter SDK for [ScryWatch](https://scrywatch.com) — session tracking, crash reporting, and log monitoring for iOS and Android apps.

## Install

In `pubspec.yaml`:

```yaml
dependencies:
  scrywatch: ^1.0.0
```

```bash
flutter pub get
```

## Quick Start

```dart
import 'package:scrywatch/scrywatch.dart';

final monitor = LogClient(
  endpoint: 'https://api.scrywatch.com',
  apiKey: 'YOUR_API_KEY',
  service: 'my-app',
  environment: 'production',
);

monitor.startSession();
monitor.log(LogLevel.info, 'App started');
monitor.logNavigation('/home');
```

## Lifecycle Integration

Add `WidgetsBindingObserver` to your root widget to flush on app pause:

```dart
class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  late final LogClient monitor;

  @override
  void initState() {
    super.initState();
    monitor = LogClient(
      endpoint: 'https://api.scrywatch.com',
      apiKey: 'YOUR_API_KEY',
    );
    WidgetsBinding.instance.addObserver(this);
    monitor.startSession();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    monitor.dispose();
    super.dispose();
  }
}
```

## Methods

| Method | Description |
|--------|-------------|
| `startSession()` | Begin a new session |
| `endSession()` | End current session |
| `setUserId(id)` | Tag subsequent logs with user ID |
| `identify(userId, {traits})` | Identify the current user (see below) — returns `Future<void>` |
| `getDeviceId()` | Returns the persisted anonymous device id — `Future<String>` |
| `log(level, message, {metadata?})` | Log at a level |
| `logError(error, stackTrace?)` | Log an error with stack trace |
| `logNavigation(screen)` | Log a screen navigation |
| `logApiCall(method, url, statusCode, durationMs)` | Log an API call (wire type: `api_call`) |
| `flush()` | Manually flush buffered events — returns `Future<void>` |
| `dispose()` | Flush and release resources |

## Identity

Every `LogClient` carries an anonymous **`device_id`** — a random UUID
generated on first use and persisted via `shared_preferences` under
`scrywatch_device_id` (falling back to an in-memory id if
`shared_preferences` is unavailable). It's sent as a top-level `device_id`
field with every ingest request, giving you cross-session continuity for
anonymous users with zero app code, and it survives app restarts.

When you know who the user is, call `identify()` to upgrade them from
anonymous to known:

```dart
await monitor.identify(
  'user_123',
  traits: {'email': 'jane@example.com', 'name': 'Jane Doe'},
);
```

This does two things:
1. Tags all subsequent events with `user_id: 'user_123'` (same as `setUserId`).
2. Sends `{ user_id, traits }` to `POST {endpoint}/api/identify` so the
   dashboard can resolve the user's email/name.

`identify()` never throws — a failed request is caught internally and
otherwise ignored, so it's always safe to call from your login flow.

## Platforms

| Platform | Detected as |
|----------|-------------|
| iOS | `ios` |
| Android | `android` |
| macOS | `macos` |
| Windows | `windows` |
| Linux | `linux` |
| Other | `unknown` |

## Dependency note

This package depends on [`package:http`](https://pub.dev/packages/http) for
HTTP requests and [`package:shared_preferences`](https://pub.dev/packages/shared_preferences)
to persist the anonymous `device_id` across app restarts. No other dependencies.

## License

MIT
