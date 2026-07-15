// The masking golden gate: proves that a captured (RepaintBoundary) frame
// has every PII region occluded with the solid mask color, and that only
// the explicitly-revealed safe element is visible.
//
// This is a pixel-level assertion against the actual captured image bytes
// — not a widget-tree assertion — because the whole point of deny-by
// -default masking is that the *pixels that leave the device* are safe,
// regardless of what the widget tree "contains".
//
// NOTE on the harness: `RenderRepaintBoundary.toImage()` performs real
// (non-faked) async rasterization, so it MUST run inside `tester.runAsync`.
// Awaiting it directly under `testWidgets`' fake-async zone never completes
// and the test hangs until timeout. The capture + byte read below are the
// only things that go inside `runAsync`; the render-box geometry lookups and
// the pixel assertions are ordinary synchronous test code.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scrywatch_replay/src/mask.dart';

/// Reads the pixel at ([x], [y]) out of raw RGBA [bytes] for an image of
/// the given [width], returning it packed as 0xRRGGBB (alpha dropped).
int _pixel(ByteData bytes, int width, int x, int y) {
  final int o = (y * width + x) * 4;
  return (bytes.getUint8(o) << 16) |
      (bytes.getUint8(o + 1) << 8) |
      bytes.getUint8(o + 2);
}

/// Returns the center point of [key]'s render box, in the coordinate
/// space of [ancestor] — i.e. the same coordinate space a
/// `toImage()` capture of [ancestor] uses.
Offset _centerOf(GlobalKey key, RenderBox ancestor) {
  final RenderBox box = key.currentContext!.findRenderObject()! as RenderBox;
  return box.localToGlobal(box.size.center(Offset.zero), ancestor: ancestor);
}

/// A point near the edge of [key]'s render box (away from its center), in
/// the coordinate space of [ancestor]. Used to sample background pixels for
/// widgets whose content (e.g. left-aligned text) doesn't fill their whole
/// box, so the sample isn't accidentally sitting on an anti-aliased glyph.
Offset _edgeOf(GlobalKey key, RenderBox ancestor) {
  final RenderBox box = key.currentContext!.findRenderObject()! as RenderBox;
  final Offset corner = box.size.bottomRight(Offset.zero) - const Offset(6, 6);
  return box.localToGlobal(corner, ancestor: ancestor);
}

/// Captures [boundaryKey]'s current frame and runs the production redaction
/// path (`computeMaskGeometry` + `maskImage`) over it — this is what the
/// recorder uploads. Must run inside `tester.runAsync` (see the harness note
/// at the top of this file); this helper does that internally so call sites
/// stay ordinary `await` calls.
Future<(ByteData data, int width)> _captureMasked(
  WidgetTester tester,
  GlobalKey boundaryKey,
) async {
  late final ByteData data;
  late final int imgWidth;
  await tester.runAsync(() async {
    final RenderRepaintBoundary boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final ui.Image raw = await boundary.toImage(pixelRatio: 1.0);
    final MaskGeometry geometry = computeMaskGeometry(
      boundaryKey.currentContext!,
      boundary,
    );
    final double scale = raw.width / boundary.size.width;
    final ui.Image masked = await maskImage(raw, geometry, scale: scale);
    data = (await masked.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    imgWidth = masked.width;
    raw.dispose();
    masked.dispose();
  });
  return (data, imgWidth);
}

/// Synchronously-usable `dart:ui.Image` for tests: a solid-[color] square
/// rendered ahead of time inside `runAsync`, so widgets under test (e.g.
/// [RawImage]) can be built with a fully-decoded image and don't need to
/// wait on a real async codec during `pump`/`pumpAndSettle` (which — like
/// `toImage()` — can't complete under `testWidgets`' fake-async zone; see
/// the harness note at the top of this file).
Future<ui.Image> _makeTestImage(
  WidgetTester tester, {
  int width = 8,
  int height = 8,
  Color color = const Color(0xFF3366FF),
}) async {
  late final ui.Image image;
  await tester.runAsync(() async {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = color,
    );
    final ui.Picture picture = recorder.endRecording();
    image = await picture.toImage(width, height);
  });
  return image;
}

void main() {
  // Deterministic starting policy for every test, regardless of run order —
  // MaskRegistry is a process-wide singleton (see its doc comment), so a
  // policy set by one test would otherwise leak into the next.
  setUp(() => MaskRegistry.instance.setPolicy(const MaskPolicy()));

  testWidgets(
    'PII regions are fully occluded; revealed safe element is visible',
    (WidgetTester tester) async {
      final GlobalKey boundaryKey = GlobalKey();
      final GlobalKey emailKey = GlobalKey();
      final GlobalKey cardKey = GlobalKey();
      final GlobalKey passwordKey = GlobalKey();
      final GlobalKey safeKey = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          home: maskedRoot(
            boundaryKey: boundaryKey,
            child: Scaffold(
              body: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('test@example.com', key: emailKey),
                  Text('4242 4242 4242 4242', key: cardKey),
                  TextField(key: passwordKey, obscureText: true),
                  ScrywatchReveal(
                    child: Container(
                      key: safeKey,
                      color: const Color(0xFF00FF00),
                      width: 100,
                      height: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Geometry lookups are synchronous and use the laid-out render tree.
      final RenderBox boundaryBox =
          boundaryKey.currentContext!.findRenderObject()! as RenderBox;
      final Offset emailCenter = _centerOf(emailKey, boundaryBox);
      final Offset cardCenter = _centerOf(cardKey, boundaryBox);
      final Offset passwordCenter = _centerOf(passwordKey, boundaryBox);
      final Offset safeCenter = _centerOf(safeKey, boundaryBox);

      final (ByteData data, int imgWidth) = await _captureMasked(
        tester,
        boundaryKey,
      );

      // Deny-by-default: nothing here was wrapped in ScrywatchReveal, so
      // every one of these must be occluded with the solid mask color.
      expect(
        _pixel(data, imgWidth, emailCenter.dx.round(), emailCenter.dy.round()),
        equals(kMaskColorRgb),
        reason: 'email text must be masked, not visible in the capture',
      );
      expect(
        _pixel(data, imgWidth, cardCenter.dx.round(), cardCenter.dy.round()),
        equals(kMaskColorRgb),
        reason: 'card number text must be masked, not visible in the capture',
      );
      expect(
        _pixel(
          data,
          imgWidth,
          passwordCenter.dx.round(),
          passwordCenter.dy.round(),
        ),
        equals(kMaskColorRgb),
        reason: 'obscureText field must always be masked',
      );

      // The only explicitly-revealed element must show through untouched.
      expect(
        _pixel(data, imgWidth, safeCenter.dx.round(), safeCenter.dy.round()),
        equals(0x00FF00),
        reason: 'ScrywatchReveal-wrapped safe element must be visible',
      );
    },
  );

  testWidgets(
    'blocklist mode masks a ScrywatchTag-tagged element via a tag rule',
    (WidgetTester tester) async {
      final GlobalKey boundaryKey = GlobalKey();
      final GlobalKey taggedKey = GlobalKey();

      MaskRegistry.instance.setPolicy(
        const MaskPolicy(
          mode: MaskMode.blocklist,
          rules: <MaskRule>[
            MaskRule(match: MaskMatch.tag, value: 'secret'),
          ],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: maskedRoot(
            boundaryKey: boundaryKey,
            child: Scaffold(
              body: ScrywatchTag(
                'secret',
                child: Container(
                  key: taggedKey,
                  color: const Color(0xFF00FF00),
                  width: 100,
                  height: 20,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final RenderBox boundaryBox =
          boundaryKey.currentContext!.findRenderObject()! as RenderBox;
      final Offset taggedCenter = _centerOf(taggedKey, boundaryBox);

      final (ByteData data, int imgWidth) = await _captureMasked(
        tester,
        boundaryKey,
      );

      expect(
        _pixel(
          data,
          imgWidth,
          taggedCenter.dx.round(),
          taggedCenter.dy.round(),
        ),
        equals(kMaskColorRgb),
        reason: 'tag-ruled element must be masked in blocklist mode',
      );
    },
  );

  group('the always-on PII floor (blocklist mode)', () {
    testWidgets(
      'an untagged Text containing an email address is masked',
      (WidgetTester tester) async {
        MaskRegistry.instance.setPolicy(const MaskPolicy());
        final GlobalKey boundaryKey = GlobalKey();
        final GlobalKey emailKey = GlobalKey();

        await tester.pumpWidget(
          MaterialApp(
            home: maskedRoot(
              boundaryKey: boundaryKey,
              child: Scaffold(
                body: Container(
                  key: emailKey,
                  color: const Color(0xFFFFFFFF),
                  width: 220,
                  height: 40,
                  child: const Text('user@example.com'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final RenderBox boundaryBox =
            boundaryKey.currentContext!.findRenderObject()! as RenderBox;
        final Offset center = _centerOf(emailKey, boundaryBox);
        final (ByteData data, int imgWidth) = await _captureMasked(
          tester,
          boundaryKey,
        );

        expect(
          _pixel(data, imgWidth, center.dx.round(), center.dy.round()),
          equals(kMaskColorRgb),
          reason:
              'an untagged email string must still be masked by the PII floor',
        );
      },
    );

    testWidgets(
      'an untagged Text containing a Luhn-valid card number is masked',
      (WidgetTester tester) async {
        MaskRegistry.instance.setPolicy(const MaskPolicy());
        final GlobalKey boundaryKey = GlobalKey();
        final GlobalKey cardKey = GlobalKey();

        await tester.pumpWidget(
          MaterialApp(
            home: maskedRoot(
              boundaryKey: boundaryKey,
              child: Scaffold(
                body: Container(
                  key: cardKey,
                  color: const Color(0xFFFFFFFF),
                  width: 220,
                  height: 40,
                  child: const Text('4242 4242 4242 4242'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final RenderBox boundaryBox =
            boundaryKey.currentContext!.findRenderObject()! as RenderBox;
        final Offset center = _centerOf(cardKey, boundaryBox);
        final (ByteData data, int imgWidth) = await _captureMasked(
          tester,
          boundaryKey,
        );

        expect(
          _pixel(data, imgWidth, center.dx.round(), center.dy.round()),
          equals(kMaskColorRgb),
          reason:
              'a Luhn-valid card number must be masked by the PII floor',
        );
      },
    );

    testWidgets(
      'an untagged Text with no PII is NOT masked in blocklist mode',
      (WidgetTester tester) async {
        MaskRegistry.instance.setPolicy(const MaskPolicy());
        final GlobalKey boundaryKey = GlobalKey();
        final GlobalKey plainKey = GlobalKey();
        const Color bg = Color(0xFFFFFFFF);

        await tester.pumpWidget(
          MaterialApp(
            home: maskedRoot(
              boundaryKey: boundaryKey,
              child: Scaffold(
                body: Container(
                  key: plainKey,
                  color: bg,
                  width: 220,
                  height: 40,
                  child: const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('hello world'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final RenderBox boundaryBox =
            boundaryKey.currentContext!.findRenderObject()! as RenderBox;
        // Sample near the box's far edge, clear of the left-aligned glyphs.
        final Offset edge = _edgeOf(plainKey, boundaryBox);
        final (ByteData data, int imgWidth) = await _captureMasked(
          tester,
          boundaryKey,
        );

        expect(
          _pixel(data, imgWidth, edge.dx.round(), edge.dy.round()),
          equals(0xFFFFFF),
          reason:
              'plain, untagged, non-PII text must record in the clear in '
              'blocklist mode (record-everything-except-matched default)',
        );
      },
    );

    testWidgets(
      'an obscureText field is always masked in blocklist mode',
      (WidgetTester tester) async {
        MaskRegistry.instance.setPolicy(const MaskPolicy());
        final GlobalKey boundaryKey = GlobalKey();
        final GlobalKey passwordKey = GlobalKey();

        await tester.pumpWidget(
          MaterialApp(
            home: maskedRoot(
              boundaryKey: boundaryKey,
              child: Scaffold(
                body: TextField(key: passwordKey, obscureText: true),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final RenderBox boundaryBox =
            boundaryKey.currentContext!.findRenderObject()! as RenderBox;
        final Offset center = _centerOf(passwordKey, boundaryBox);
        final (ByteData data, int imgWidth) = await _captureMasked(
          tester,
          boundaryKey,
        );

        expect(
          _pixel(data, imgWidth, center.dx.round(), center.dy.round()),
          equals(kMaskColorRgb),
          reason: 'obscureText fields are floor-masked in every mode',
        );
      },
    );
  });

  group('scrywatchIsPii', () {
    test('detects an email address embedded in a longer string', () {
      expect(scrywatchIsPii('contact me at user@example.com please'), isTrue);
    });

    test('detects a Luhn-valid card number', () {
      expect(scrywatchIsPii('4242 4242 4242 4242'), isTrue);
    });

    test('does not flag a Luhn-invalid digit run of card length', () {
      expect(scrywatchIsPii('4242 4242 4242 4241'), isFalse);
    });

    test('detects an SSN', () {
      expect(scrywatchIsPii('SSN: 123-45-6789'), isTrue);
    });

    test('detects a US-style phone number', () {
      expect(scrywatchIsPii('call 415-555-0132'), isTrue);
    });

    test('does not flag plain text', () {
      expect(scrywatchIsPii('hello world'), isFalse);
    });

    test('does not flag a short, non-PII digit run', () {
      expect(scrywatchIsPii('order #12345'), isFalse);
    });

    test('does not flag empty text', () {
      expect(scrywatchIsPii(''), isFalse);
    });
  });

  group('mode-aware compositing', () {
    testWidgets(
      'blocklist: tag + image rules mask their matches; plain and '
      'revealed text stay visible',
      (WidgetTester tester) async {
        final ui.Image demoImage = await _makeTestImage(tester);

        MaskRegistry.instance.setPolicy(
          const MaskPolicy(
            mode: MaskMode.blocklist,
            rules: <MaskRule>[
              MaskRule(match: MaskMatch.tag, value: 'workout-notes'),
              MaskRule(match: MaskMatch.widgetType, value: 'image'),
            ],
          ),
        );

        final GlobalKey boundaryKey = GlobalKey();
        final GlobalKey taggedKey = GlobalKey();
        final GlobalKey imageKey = GlobalKey();
        final GlobalKey plainKey = GlobalKey();
        final GlobalKey revealedKey = GlobalKey();
        const Color bg = Color(0xFFFFFFFF);

        await tester.pumpWidget(
          MaterialApp(
            home: maskedRoot(
              boundaryKey: boundaryKey,
              child: Scaffold(
                body: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // Matched by the `tag` rule — no PII, wouldn't be
                    // floor-masked on its own.
                    ScrywatchTag(
                      'workout-notes',
                      child: Container(
                        key: taggedKey,
                        color: bg,
                        width: 220,
                        height: 40,
                        child: const Align(
                          alignment: Alignment.centerLeft,
                          child: Text('prefers morning runs'),
                        ),
                      ),
                    ),
                    // Matched by the `widgetType: image` rule.
                    RawImage(key: imageKey, image: demoImage, width: 80, height: 40),
                    // Untagged, non-PII, no rule match — must record in
                    // the clear under blocklist's record-everything default.
                    Container(
                      key: plainKey,
                      color: bg,
                      width: 220,
                      height: 40,
                      child: const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('just a caption'),
                      ),
                    ),
                    // Explicitly revealed marketing copy — reveal is a
                    // no-op in blocklist mode (nothing to reveal FROM), it
                    // simply stays visible like any other unmatched text.
                    ScrywatchReveal(
                      child: Container(
                        key: revealedKey,
                        color: bg,
                        width: 220,
                        height: 40,
                        child: const Align(
                          alignment: Alignment.centerLeft,
                          child: Text('50% off summer plans'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final RenderBox boundaryBox =
            boundaryKey.currentContext!.findRenderObject()! as RenderBox;
        final Offset taggedCenter = _centerOf(taggedKey, boundaryBox);
        final Offset imageCenter = _centerOf(imageKey, boundaryBox);
        final Offset plainEdge = _edgeOf(plainKey, boundaryBox);
        final Offset revealedEdge = _edgeOf(revealedKey, boundaryBox);

        final (ByteData data, int imgWidth) = await _captureMasked(
          tester,
          boundaryKey,
        );

        expect(
          _pixel(
            data,
            imgWidth,
            taggedCenter.dx.round(),
            taggedCenter.dy.round(),
          ),
          equals(kMaskColorRgb),
          reason: 'tag-ruled element must be masked',
        );
        expect(
          _pixel(
            data,
            imgWidth,
            imageCenter.dx.round(),
            imageCenter.dy.round(),
          ),
          equals(kMaskColorRgb),
          reason: 'widgetType:image-ruled element must be masked',
        );
        expect(
          _pixel(data, imgWidth, plainEdge.dx.round(), plainEdge.dy.round()),
          equals(0xFFFFFF),
          reason:
              'plain untagged non-PII text must record in the clear '
              '(blocklist default)',
        );
        expect(
          _pixel(
            data,
            imgWidth,
            revealedEdge.dx.round(),
            revealedEdge.dy.round(),
          ),
          equals(0xFFFFFF),
          reason:
              'a ScrywatchReveal wrapper is a no-op in blocklist mode; the '
              'text stays visible because nothing matched it',
        );
      },
    );

    testWidgets(
      'strict: everything is masked except a ScrywatchReveal element, but '
      'PII inside a reveal is still masked (the floor beats reveal)',
      (WidgetTester tester) async {
        MaskRegistry.instance.setPolicy(const MaskPolicy(mode: MaskMode.strict));

        final GlobalKey boundaryKey = GlobalKey();
        final GlobalKey safeKey = GlobalKey();
        final GlobalKey plainKey = GlobalKey();
        final GlobalKey piiInRevealKey = GlobalKey();

        await tester.pumpWidget(
          MaterialApp(
            home: maskedRoot(
              boundaryKey: boundaryKey,
              child: Scaffold(
                body: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // Explicitly revealed, non-PII — the only thing that
                    // should show through in strict mode.
                    ScrywatchReveal(
                      child: Container(
                        key: safeKey,
                        color: const Color(0xFF00FF00),
                        width: 100,
                        height: 20,
                      ),
                    ),
                    // Not revealed at all — masked by strict's
                    // deny-by-default baseline.
                    Text('untouched plain text', key: plainKey),
                    // Revealed, but PII — the floor must win over the
                    // reveal.
                    ScrywatchReveal(
                      child: Text(
                        'user@example.com',
                        key: piiInRevealKey,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final RenderBox boundaryBox =
            boundaryKey.currentContext!.findRenderObject()! as RenderBox;
        final Offset safeCenter = _centerOf(safeKey, boundaryBox);
        final Offset plainCenter = _centerOf(plainKey, boundaryBox);
        final Offset piiCenter = _centerOf(piiInRevealKey, boundaryBox);

        final (ByteData data, int imgWidth) = await _captureMasked(
          tester,
          boundaryKey,
        );

        expect(
          _pixel(data, imgWidth, safeCenter.dx.round(), safeCenter.dy.round()),
          equals(0x00FF00),
          reason: 'ScrywatchReveal-wrapped non-PII element must be visible',
        );
        expect(
          _pixel(
            data,
            imgWidth,
            plainCenter.dx.round(),
            plainCenter.dy.round(),
          ),
          equals(kMaskColorRgb),
          reason: 'un-revealed text is masked by the strict baseline',
        );
        expect(
          _pixel(data, imgWidth, piiCenter.dx.round(), piiCenter.dy.round()),
          equals(kMaskColorRgb),
          reason:
              'PII inside a ScrywatchReveal must still be masked — the '
              'floor beats reveal',
        );
      },
    );
  });

  group('blocklist fail-safe on unresolved hard-mask keys', () {
    testWidgets(
      'a registered ScrywatchMask key that never resolves to a rect marks '
      'resolutionIncomplete',
      (WidgetTester tester) async {
        MaskRegistry.instance.setPolicy(const MaskPolicy(mode: MaskMode.blocklist));

        final GlobalKey boundaryKey = GlobalKey();
        // Registered as a hard-mask key directly on the registry, but never
        // built anywhere in the widget tree below — currentContext stays
        // null forever, which is exactly what happens for a real
        // ScrywatchMask/tag/rule element mid-relayout, just-mounted, or
        // mid-unmount on a given frame.
        final GlobalKey unresolvedKey = GlobalKey();
        MaskRegistry.instance.registerMask(unresolvedKey);
        addTearDown(() => MaskRegistry.instance.unregisterMask(unresolvedKey));

        await tester.pumpWidget(
          MaterialApp(
            home: maskedRoot(
              boundaryKey: boundaryKey,
              child: const Scaffold(
                body: Text('nothing sensitive here'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final RenderBox boundaryBox =
            boundaryKey.currentContext!.findRenderObject()! as RenderBox;
        final MaskGeometry geometry = computeMaskGeometry(
          boundaryKey.currentContext!,
          boundaryBox,
        );

        expect(
          geometry.resolutionIncomplete,
          isTrue,
          reason:
              'a hard-mask key present in the registry but unresolvable '
              'this frame must set resolutionIncomplete',
        );
      },
    );

    testWidgets(
      'blocklist mode occludes the ENTIRE captured frame when '
      'resolutionIncomplete is true',
      (WidgetTester tester) async {
        MaskRegistry.instance.setPolicy(const MaskPolicy(mode: MaskMode.blocklist));

        final GlobalKey boundaryKey = GlobalKey();
        final GlobalKey unresolvedKey = GlobalKey();
        MaskRegistry.instance.registerMask(unresolvedKey);
        addTearDown(() => MaskRegistry.instance.unregisterMask(unresolvedKey));

        await tester.pumpWidget(
          MaterialApp(
            home: maskedRoot(
              boundaryKey: boundaryKey,
              child: const Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 200,
                    height: 100,
                    child: ColoredBox(color: Color(0xFF00FF00)),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final RenderBox boundaryBox =
            boundaryKey.currentContext!.findRenderObject()! as RenderBox;
        final Size boxSize = boundaryBox.size;

        final (ByteData data, int imgWidth) = await _captureMasked(
          tester,
          boundaryKey,
        );

        // Sample several points spread across the frame — corners and
        // center — to confirm the WHOLE frame is masked, not just whatever
        // rects happened to resolve.
        final List<Offset> samples = <Offset>[
          const Offset(2, 2),
          Offset(boxSize.width - 3, 2),
          Offset(2, boxSize.height - 3),
          Offset(boxSize.width - 3, boxSize.height - 3),
          Offset(boxSize.width / 2, boxSize.height / 2),
        ];
        for (final Offset s in samples) {
          expect(
            _pixel(data, imgWidth, s.dx.round(), s.dy.round()),
            equals(kMaskColorRgb),
            reason:
                'blocklist must mask-all when resolutionIncomplete is true '
                '(sample at $s) — an unresolved hard-mask key can never '
                'result in a partially-masked, potentially leaking frame',
          );
        }
      },
    );
  });

  group('RichText PII floor', () {
    testWidgets(
      'an untagged RichText containing an email address is masked',
      (WidgetTester tester) async {
        MaskRegistry.instance.setPolicy(const MaskPolicy());
        final GlobalKey boundaryKey = GlobalKey();
        final GlobalKey richKey = GlobalKey();

        await tester.pumpWidget(
          MaterialApp(
            home: maskedRoot(
              boundaryKey: boundaryKey,
              child: Scaffold(
                body: Container(
                  key: richKey,
                  color: const Color(0xFFFFFFFF),
                  width: 220,
                  height: 40,
                  child: RichText(
                    text: const TextSpan(
                      text: 'user@example.com',
                      style: TextStyle(color: Color(0xFF000000)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final RenderBox boundaryBox =
            boundaryKey.currentContext!.findRenderObject()! as RenderBox;
        final Offset center = _centerOf(richKey, boundaryBox);
        final (ByteData data, int imgWidth) = await _captureMasked(
          tester,
          boundaryKey,
        );

        expect(
          _pixel(data, imgWidth, center.dx.round(), center.dy.round()),
          equals(kMaskColorRgb),
          reason:
              'an untagged RichText carrying PII must be masked by the '
              'floor, same as Text',
        );
      },
    );

    testWidgets(
      'an untagged RichText with no PII is NOT masked in blocklist mode',
      (WidgetTester tester) async {
        MaskRegistry.instance.setPolicy(const MaskPolicy());
        final GlobalKey boundaryKey = GlobalKey();
        final GlobalKey richKey = GlobalKey();
        const Color bg = Color(0xFFFFFFFF);

        await tester.pumpWidget(
          MaterialApp(
            home: maskedRoot(
              boundaryKey: boundaryKey,
              child: Scaffold(
                body: Container(
                  key: richKey,
                  color: bg,
                  width: 220,
                  height: 40,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: RichText(
                      text: const TextSpan(
                        text: 'hello world',
                        style: TextStyle(color: Color(0xFF000000)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final RenderBox boundaryBox =
            boundaryKey.currentContext!.findRenderObject()! as RenderBox;
        final Offset edge = _edgeOf(richKey, boundaryBox);
        final (ByteData data, int imgWidth) = await _captureMasked(
          tester,
          boundaryKey,
        );

        expect(
          _pixel(data, imgWidth, edge.dx.round(), edge.dy.round()),
          equals(0xFFFFFF),
          reason:
              'plain, non-PII RichText content must record in the clear '
              'in blocklist mode',
        );
      },
    );
  });

  // Remote policy: the SDK fetches the mask policy as JSON over the wire,
  // so parsing it must be defensively tolerant — a malformed/unexpected
  // server response must never crash the app or silently produce a policy
  // that masks LESS than the safe default. See
  // ReplayRecorder._fetchAndApplyPolicy in recorder.dart for the
  // fetch/fail-safe side of this contract.
  group('MaskPolicy.fromJson', () {
    test('parses a valid policy with mode, rules, and version', () {
      final MaskPolicy policy = MaskPolicy.fromJson(<String, dynamic>{
        'mode': 'strict',
        'rules': <Map<String, dynamic>>[
          <String, dynamic>{'match': 'tag', 'value': 'workout-notes'},
          <String, dynamic>{'match': 'widgetType', 'value': 'image'},
          <String, dynamic>{'match': 'textPattern', 'value': 'email'},
        ],
        'version': 3,
      });

      expect(policy.mode, MaskMode.strict);
      expect(policy.version, 3);
      expect(policy.rules, hasLength(3));
      expect(policy.rules[0].match, MaskMatch.tag);
      expect(policy.rules[0].value, 'workout-notes');
      expect(policy.rules[1].match, MaskMatch.widgetType);
      expect(policy.rules[1].value, 'image');
      expect(policy.rules[2].match, MaskMatch.textPattern);
      expect(policy.rules[2].value, 'email');
    });

    test('parses an explicit blocklist mode with no rules', () {
      final MaskPolicy policy = MaskPolicy.fromJson(<String, dynamic>{
        'mode': 'blocklist',
        'rules': <Map<String, dynamic>>[],
        'version': 1,
      });

      expect(policy.mode, MaskMode.blocklist);
      expect(policy.rules, isEmpty);
      expect(policy.version, 1);
    });

    test(
      'a rule with an unknown match value is dropped; valid rules survive',
      () {
        final MaskPolicy policy = MaskPolicy.fromJson(<String, dynamic>{
          'mode': 'blocklist',
          'rules': <Map<String, dynamic>>[
            <String, dynamic>{'match': 'tag', 'value': 'good-tag'},
            <String, dynamic>{'match': 'somethingUnknown', 'value': 'x'},
          ],
        });

        expect(policy.rules, hasLength(1));
        expect(policy.rules.single.match, MaskMatch.tag);
        expect(policy.rules.single.value, 'good-tag');
      },
    );

    test(
      'a rule with a missing or empty value is dropped; valid rules survive',
      () {
        final MaskPolicy policy = MaskPolicy.fromJson(<String, dynamic>{
          'rules': <Map<String, dynamic>>[
            <String, dynamic>{'match': 'tag'}, // no value at all
            <String, dynamic>{'match': 'tag', 'value': ''}, // empty value
            <String, dynamic>{'match': 'widgetType', 'value': 'webview'},
          ],
        });

        expect(policy.rules, hasLength(1));
        expect(policy.rules.single.match, MaskMatch.widgetType);
        expect(policy.rules.single.value, 'webview');
      },
    );

    test(
      'a non-Map element in rules is dropped rather than throwing',
      () {
        final MaskPolicy policy = MaskPolicy.fromJson(<String, dynamic>{
          'rules': <dynamic>[
            'not-a-rule-object',
            42,
            <String, dynamic>{'match': 'tag', 'value': 'kept'},
          ],
        });

        expect(policy.rules, hasLength(1));
        expect(policy.rules.single.value, 'kept');
      },
    );

    test('missing mode defaults to blocklist (the safe default)', () {
      final MaskPolicy policy = MaskPolicy.fromJson(<String, dynamic>{});

      expect(policy.mode, MaskMode.blocklist);
      expect(policy.rules, isEmpty);
      expect(policy.version, 0);
    });

    test('a garbage mode value falls back to blocklist', () {
      final MaskPolicy policy = MaskPolicy.fromJson(<String, dynamic>{
        'mode': 'not-a-real-mode',
      });

      expect(policy.mode, MaskMode.blocklist);
    });

    test('a missing rules array yields an empty rule list', () {
      final MaskPolicy policy = MaskPolicy.fromJson(<String, dynamic>{
        'mode': 'strict',
      });

      expect(policy.mode, MaskMode.strict);
      expect(policy.rules, isEmpty);
    });
  });
}
