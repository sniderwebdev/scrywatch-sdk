/// ScryWatch Flutter SDK
///
/// Log monitoring and session tracking for Flutter apps.
///
/// Example:
/// ```dart
/// final client = LogClient(
///   endpoint: 'https://api.scrywatch.com',
///   apiKey: 'YOUR_API_KEY',
///   service: 'my-app',
///   environment: 'production',
/// );
/// client.startSession();
/// client.log(LogLevel.info, 'App started');
/// ```
library scrywatch;

export 'log_client.dart' show LogClient, LogLevel, LogType, LogEvent;
