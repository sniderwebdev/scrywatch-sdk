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
| `log(level, message, {metadata?})` | Log at a level |
| `logError(error, stackTrace?)` | Log an error with stack trace |
| `logNavigation(screen)` | Log a screen navigation |
| `logApiCall(method, url, statusCode, durationMs)` | Log an API call (wire type: `api_call`) |
| `flush()` | Manually flush buffered events — returns `Future<void>` |
| `dispose()` | Flush and release resources |

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

This package depends on [`package:http`](https://pub.dev/packages/http) for HTTP requests. No other dependencies.

## License

MIT
