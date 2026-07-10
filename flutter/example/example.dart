import 'package:scrywatch/scrywatch.dart';

Future<void> main() async {
  final client = LogClient(
    endpoint: 'https://api.scrywatch.com',
    apiKey: 'YOUR_API_KEY',
    service: 'my-app',
    environment: 'production',
  );

  // Start a session so related events are grouped together.
  client.startSession();

  client.log(LogLevel.info, 'App started');
  client.log(
    LogLevel.error,
    'Checkout failed',
    metadata: {'order_id': '456', 'reason': 'card_declined'},
  );

  // Events are flushed automatically on an interval; flush manually before exit.
  await client.flush();
  client.dispose();
}
