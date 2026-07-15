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

        final SharedPreferences prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('replay_session_id'), recorder.sessionId);
      },
    );

    testWidgets(
      'clearSession empties the session id, resets the sequence, and '
      'removes the persisted pref',
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

        final SharedPreferences prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('replay_session_id'), isNull);
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
