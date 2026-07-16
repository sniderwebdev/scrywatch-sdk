// Recorder-side hardening tests (see recorder.dart doc comments for the
// fail-safe contracts these exercise): upload failures must never crash the
// app, sessions must rotate/clear cleanly, and no frame may ever be
// attributed to an empty session id.
//
// NOTE on the harness: capturing a real frame (`RenderRepaintBoundary
// .toImage()`) performs real async rasterization, so any test that expects
// `debugTick()` to reach the upload path (i.e. capture must succeed) has to
// run inside `tester.runAsync` — see the same note in
// masking_golden_test.dart. Tests that only exercise the early-return guards
// (empty session, no consent) don't need a mounted boundary or `runAsync`.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:scrywatch_replay/src/mask.dart';
import 'package:scrywatch_replay/src/recorder.dart';

/// A [MockClient] that answers `GET /api/replay/policy` with a harmless
/// non-200 (so `start()`'s fail-safe policy fetch is a no-op) and routes
/// `POST /api/replay` uploads to [onUpload].
MockClient _client(
  Future<http.Response> Function(http.Request request) onUpload,
) {
  return MockClient((http.Request request) async {
    if (request.url.path.endsWith('/api/replay/policy')) {
      return http.Response('', 500);
    }
    if (request.url.path.endsWith('/api/replay')) {
      return onUpload(request);
    }
    return http.Response('not found', 404);
  });
}

Future<GlobalKey> _mountBoundary(WidgetTester tester) async {
  final GlobalKey boundaryKey = GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      home: maskedRoot(
        boundaryKey: boundaryKey,
        child: const Scaffold(body: Text('hello')),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return boundaryKey;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    MaskRegistry.instance.setPolicy(const MaskPolicy());
  });

  group('upload fail-safe', () {
    testWidgets(
      'a thrown ClientException during upload is caught, counted as '
      'dropped, and never rethrown',
      (WidgetTester tester) async {
        int uploadAttempts = 0;
        final MockClient client = _client((http.Request request) async {
          uploadAttempts++;
          throw http.ClientException('connection refused');
        });

        final GlobalKey boundaryKey = await _mountBoundary(tester);
        final ReplayRecorder recorder = ReplayRecorder(
          endpoint: 'https://example.test',
          apiKey: 'test-key',
          boundaryKey: boundaryKey,
          httpClient: client,
        );
        await recorder.start();
        recorder.setConsent(true);

        await tester.runAsync(() => recorder.debugTick());

        expect(uploadAttempts, 1);
        expect(recorder.droppedFrames, 1);
        // Nothing rethrew — reaching this line at all is the assertion.
      },
    );

    testWidgets(
      'a timeout during upload is caught, counted as dropped, and never '
      'rethrown',
      (WidgetTester tester) async {
        int uploadAttempts = 0;
        final MockClient client = _client((http.Request request) async {
          uploadAttempts++;
          // Simulate the .timeout(_kUploadTimeout) firing without making the
          // test wait out a real 10-second timer.
          throw TimeoutException('upload timed out');
        });

        final GlobalKey boundaryKey = await _mountBoundary(tester);
        final ReplayRecorder recorder = ReplayRecorder(
          endpoint: 'https://example.test',
          apiKey: 'test-key',
          boundaryKey: boundaryKey,
          httpClient: client,
        );
        await recorder.start();
        recorder.setConsent(true);

        await tester.runAsync(() => recorder.debugTick());

        expect(uploadAttempts, 1);
        expect(recorder.droppedFrames, 1);
      },
    );
  });

  group('session rotate/clear', () {
    testWidgets(
      'rotateSession mints a new session id and resets the sequence',
      (WidgetTester tester) async {
        final MockClient client = _client(
          (http.Request request) async => http.Response('', 200),
        );
        final GlobalKey boundaryKey = await _mountBoundary(tester);
        final ReplayRecorder recorder = ReplayRecorder(
          endpoint: 'https://example.test',
          apiKey: 'test-key',
          boundaryKey: boundaryKey,
          httpClient: client,
        );
        await recorder.start();
        recorder.setConsent(true);
        final String originalSessionId = recorder.sessionId;
        expect(originalSessionId, isNotEmpty);

        await tester.runAsync(() => recorder.debugTick());
        expect(recorder.framesSent, 1);

        await recorder.rotateSession();

        expect(recorder.sessionId, isNotEmpty);
        expect(recorder.sessionId, isNot(equals(originalSessionId)));
        expect(recorder.framesSent, 0);

        // Session ids are no longer persisted (per-launch sessions) — nothing
        // is written to the pref key.
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('replay_session_id'), isNull);
      },
    );

    testWidgets(
      'clearSession empties the session id and resets the sequence',
      (WidgetTester tester) async {
        final MockClient client = _client(
          (http.Request request) async => http.Response('', 200),
        );
        final GlobalKey boundaryKey = await _mountBoundary(tester);
        final ReplayRecorder recorder = ReplayRecorder(
          endpoint: 'https://example.test',
          apiKey: 'test-key',
          boundaryKey: boundaryKey,
          httpClient: client,
        );
        await recorder.start();
        recorder.setConsent(true);
        await tester.runAsync(() => recorder.debugTick());
        expect(recorder.framesSent, 1);

        await recorder.clearSession();

        expect(recorder.sessionId, isEmpty);
        expect(recorder.framesSent, 0);
      },
    );

    testWidgets(
      'a cold relaunch (same signed-in user) mints a NEW session id and '
      'restarts seq at 0 — no overwrite of the prior run',
      (WidgetTester tester) async {
        final List<String> uploadedKeys = <String>[]; // "<sessionId>/<seq>"
        MockClient makeClient() => _client((http.Request request) async {
              final Map<String, dynamic> meta = jsonDecode(
                request.headers['x-replay-meta']!,
              ) as Map<String, dynamic>;
              uploadedKeys.add('${meta['session_id']}/${meta['seq']}');
              return http.Response('', 200);
            });

        // First launch: one recorder instance, one signed-in user, one frame.
        final GlobalKey boundary1 = await _mountBoundary(tester);
        final ReplayRecorder first = ReplayRecorder(
          endpoint: 'https://example.test',
          apiKey: 'test-key',
          boundaryKey: boundary1,
          httpClient: makeClient(),
        );
        await first.start();
        first.setUser('user-123');
        first.setConsent(true);
        await tester.runAsync(() => first.debugTick());
        final String firstSession = first.sessionId;
        expect(first.framesSent, 1);

        // Cold relaunch: a brand-new ReplayRecorder instance (fresh _seq) for
        // the SAME signed-in user — this is what clobbered frames before.
        final GlobalKey boundary2 = await _mountBoundary(tester);
        final ReplayRecorder second = ReplayRecorder(
          endpoint: 'https://example.test',
          apiKey: 'test-key',
          boundaryKey: boundary2,
          httpClient: makeClient(),
        );
        await second.start();
        second.setUser('user-123');
        second.setConsent(true);
        await tester.runAsync(() => second.debugTick());
        final String secondSession = second.sessionId;

        // New launch → new session id, so seq 0 lands under a different key.
        expect(secondSession, isNot(equals(firstSession)));
        expect(uploadedKeys, <String>['$firstSession/0', '$secondSession/0']);
        // No two uploads share a "<sessionId>/<seq>" key → nothing overwritten.
        expect(uploadedKeys.toSet().length, uploadedKeys.length);
      },
    );
  });

  group('identity (device_id / user_id)', () {
    testWidgets(
      'a generated device_id is persisted and reused by a fresh recorder '
      '(simulated restart)',
      (WidgetTester tester) async {
        final MockClient client = _client(
          (http.Request request) async => http.Response('', 200),
        );
        final GlobalKey boundaryKey = await _mountBoundary(tester);

        final ReplayRecorder first = ReplayRecorder(
          endpoint: 'https://example.test',
          apiKey: 'test-key',
          boundaryKey: boundaryKey,
          httpClient: client,
        );
        await first.start();

        final SharedPreferences prefs = await SharedPreferences.getInstance();
        final String? persisted = prefs.getString('scrywatch_device_id');
        expect(persisted, isNotNull);
        expect(persisted, isNotEmpty);

        // Simulate an app restart: a brand-new recorder reading the same
        // (mocked) SharedPreferences backing store.
        final ReplayRecorder second = ReplayRecorder(
          endpoint: 'https://example.test',
          apiKey: 'test-key',
          boundaryKey: boundaryKey,
          httpClient: client,
        );
        await second.start();

        expect(prefs.getString('scrywatch_device_id'), persisted);
      },
    );

    testWidgets(
      'x-replay-meta on an upload includes device_id',
      (WidgetTester tester) async {
        Map<String, dynamic>? meta;
        final MockClient client = _client((http.Request request) async {
          meta = jsonDecode(request.headers['x-replay-meta']!)
              as Map<String, dynamic>;
          return http.Response('', 200);
        });
        final GlobalKey boundaryKey = await _mountBoundary(tester);
        final ReplayRecorder recorder = ReplayRecorder(
          endpoint: 'https://example.test',
          apiKey: 'test-key',
          boundaryKey: boundaryKey,
          httpClient: client,
        );
        await recorder.start();
        recorder.setConsent(true);

        await tester.runAsync(() => recorder.debugTick());

        expect(meta, isNotNull);
        expect(meta!['device_id'], isA<String>());
        expect((meta!['device_id'] as String), isNotEmpty);
      },
    );

    testWidgets(
      "setUser adds user_id to subsequent meta, and setUser(null) removes "
      'it again',
      (WidgetTester tester) async {
        final List<Map<String, dynamic>> metas = <Map<String, dynamic>>[];
        final MockClient client = _client((http.Request request) async {
          metas.add(
            jsonDecode(request.headers['x-replay-meta']!)
                as Map<String, dynamic>,
          );
          return http.Response('', 200);
        });
        final GlobalKey boundaryKey = await _mountBoundary(tester);
        final ReplayRecorder recorder = ReplayRecorder(
          endpoint: 'https://example.test',
          apiKey: 'test-key',
          boundaryKey: boundaryKey,
          httpClient: client,
        );
        await recorder.start();
        recorder.setConsent(true);

        await tester.runAsync(() => recorder.debugTick());
        expect(metas[0].containsKey('user_id'), isFalse);

        recorder.setUser('u123');
        await tester.runAsync(() => recorder.debugTick());
        expect(metas[1]['user_id'], 'u123');

        recorder.setUser(null);
        await tester.runAsync(() => recorder.debugTick());
        expect(metas[2].containsKey('user_id'), isFalse);
      },
    );

    testWidgets(
      'start() never throws when SharedPreferences has no prior values',
      (WidgetTester tester) async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final MockClient client = _client(
          (http.Request request) async => http.Response('', 200),
        );
        final GlobalKey boundaryKey = await _mountBoundary(tester);
        final ReplayRecorder recorder = ReplayRecorder(
          endpoint: 'https://example.test',
          apiKey: 'test-key',
          boundaryKey: boundaryKey,
          httpClient: client,
        );

        await expectLater(recorder.start(), completes);
      },
    );
  });

  group('empty-session-id race guard', () {
    testWidgets(
      'a tick with an empty session id never POSTs to /api/replay',
      (WidgetTester tester) async {
        bool uploadCalled = false;
        final MockClient client = _client((http.Request request) async {
          uploadCalled = true;
          return http.Response('', 200);
        });

        final GlobalKey boundaryKey = await _mountBoundary(tester);
        // Deliberately skip `start()` (which sets `_sessionId`) — mirrors
        // `resume()` firing the timer before the async `start()` completes.
        final ReplayRecorder recorder = ReplayRecorder(
          endpoint: 'https://example.test',
          apiKey: 'test-key',
          boundaryKey: boundaryKey,
          httpClient: client,
        );
        recorder.setConsent(true);
        expect(recorder.sessionId, isEmpty);

        await tester.runAsync(() => recorder.debugTick());

        expect(uploadCalled, isFalse);
        expect(recorder.framesSent, 0);
      },
    );
  });
}
