import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scrywatch/scrywatch.dart';

final RegExp _uuidRe = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('device_id', () {
    test('is generated, persisted to shared_preferences, and UUID-shaped', () async {
      final client = LogClient(
        endpoint: 'https://api.example.com',
        apiKey: 'key',
        httpClient: MockClient((request) async => http.Response('', 202)),
      );

      final id = await client.getDeviceId();
      expect(id, matches(_uuidRe));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('scrywatch_device_id'), id);

      client.dispose();
    });

    test('is reused by a fresh LogClient (simulating an app restart)', () async {
      final client1 = LogClient(
        endpoint: 'https://api.example.com',
        apiKey: 'key',
        httpClient: MockClient((request) async => http.Response('', 202)),
      );
      final id1 = await client1.getDeviceId();
      client1.dispose();

      // A new instance reading from the same (mocked) persisted storage
      // should load the existing id rather than generating a new one.
      final client2 = LogClient(
        endpoint: 'https://api.example.com',
        apiKey: 'key',
        httpClient: MockClient((request) async => http.Response('', 202)),
      );
      final id2 = await client2.getDeviceId();
      client2.dispose();

      expect(id2, id1);
    });

    test('is sent as a top-level field on the /api/ingest body, not per-event', () async {
      http.BaseRequest? captured;
      Map<String, dynamic>? capturedBody;

      final client = LogClient(
        endpoint: 'https://api.example.com',
        apiKey: 'key',
        flushInterval: const Duration(minutes: 10),
        httpClient: MockClient((request) async {
          captured = request;
          capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('', 202);
        }),
      );

      final deviceId = await client.getDeviceId();
      client.log(LogLevel.info, 'hello');
      await client.flush();

      expect(captured!.url.path, '/api/ingest');
      expect(capturedBody!['device_id'], deviceId);
      final events = capturedBody!['events'] as List;
      expect(events, hasLength(1));
      expect((events.first as Map<String, dynamic>).containsKey('device_id'), isFalse);

      client.dispose();
    });
  });

  group('identify', () {
    test('POSTs { user_id, traits } to /api/identify with Bearer auth and tags subsequent events', () async {
      http.BaseRequest? identifyRequest;
      Map<String, dynamic>? identifyBody;
      Map<String, dynamic>? ingestBody;

      final client = LogClient(
        endpoint: 'https://api.example.com',
        apiKey: 'secret-key',
        flushInterval: const Duration(minutes: 10),
        httpClient: MockClient((request) async {
          if (request.url.path == '/api/identify') {
            identifyRequest = request;
            identifyBody = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response(jsonEncode({'ok': true, 'user_id': 'user-42'}), 200);
          }
          ingestBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('', 202);
        }),
      );

      await client.identify('user-42', traits: {'email': 'a@b.com'});

      expect(identifyRequest, isNotNull);
      expect(identifyRequest!.method, 'POST');
      expect(identifyRequest!.headers['Authorization'], 'Bearer secret-key');
      expect(identifyRequest!.headers['Content-Type'], 'application/json');
      expect(identifyBody, {
        'user_id': 'user-42',
        'traits': {'email': 'a@b.com'},
      });

      client.log(LogLevel.info, 'after identify');
      await client.flush();

      final events = ingestBody!['events'] as List;
      expect((events.first as Map<String, dynamic>)['user_id'], 'user-42');

      client.dispose();
    });

    test('never throws when the underlying HTTP call fails (network error)', () async {
      final client = LogClient(
        endpoint: 'https://api.example.com',
        apiKey: 'key',
        httpClient: MockClient((request) async {
          throw Exception('network down');
        }),
      );

      await expectLater(
        client.identify('user-1', traits: {'email': 'a@b.com'}),
        completes,
      );

      client.dispose();
    });

    test('never throws on a non-2xx response', () async {
      final client = LogClient(
        endpoint: 'https://api.example.com',
        apiKey: 'key',
        httpClient: MockClient((request) async => http.Response('bad request', 400)),
      );

      await expectLater(client.identify('user-1'), completes);

      client.dispose();
    });
  });
}
