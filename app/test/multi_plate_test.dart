// The multi-plate finder ("several plates in one photo") on composited
// photos with known plates (made by ml/scripts/make_multi_plate_cases.py:
// fixture dishes laid out 10 px to 150 px apart, faint rims, mixed colony
// densities, dark and light surrounds) and on single plates, which must come
// out as one plate, never as clusters of colonies.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:colony_counter/core/pipeline.dart';
import 'package:colony_counter/core/plate.dart';
import 'package:colony_counter/data/plate_store.dart';
import 'package:colony_counter/data/storage/storage.dart';
import 'package:colony_counter/l10n/l10n.dart';
import 'package:colony_counter/ui/multi_plate_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'synth.dart';

typedef _Truth = ({double cx, double cy, double r});

/// Plates found in the photo at [path].
List<Plate> _find(String path) =>
    findPlatesInPhoto((File(path).readAsBytesSync(), PlateFormat.dish90))
        .plates;

/// Each found plate (reading order) within [tol] of the true one, relative
/// to its radius, in centre and in radius.
void _expectPlates(List<Plate> found, List<_Truth> truth, {double tol = 0.03}) {
  expect(found.length, truth.length, reason: 'number of plates');
  for (var i = 0; i < truth.length; i++) {
    final t = truth[i], f = found[i];
    final off = math.sqrt(math.pow(f.cx - t.cx, 2) + math.pow(f.cy - t.cy, 2));
    expect(off / t.r, lessThan(tol), reason: 'plate ${i + 1} centre');
    expect(
      (f.radius - t.r).abs() / t.r,
      lessThan(tol),
      reason: 'plate ${i + 1} radius',
    );
  }
}

void main() {
  final cases = (jsonDecode(
    File('test/fixtures/multi_plates.json').readAsStringSync(),
  ) as Map<String, dynamic>);

  group('composited photos with known plates', () {
    for (final MapEntry(key: file, :value) in cases.entries) {
      test(file, () {
        final truth = [
          for (final p in (value as Map)['plates'] as List)
            (
              cx: (p['cx'] as num).toDouble(),
              cy: (p['cy'] as num).toDouble(),
              r: (p['radius'] as num).toDouble(),
            ),
        ];
        _expectPlates(_find('test/fixtures/$file'), truth);
      });
    }
  });

  test('four plates 10 px apart are four plates', () {
    final t = (cases['multi_store4_gap10.jpg'] as Map)['plates'] as List;
    // The fixture really is 10 px between neighbours.
    final gap = (t[1]['cx'] as num) - (t[0]['cx'] as num) - 2 * 300;
    expect(gap, closeTo(10, 0.5));
    expect(_find('test/fixtures/multi_store4_gap10.jpg'), hasLength(4));
    expect(_find('test/fixtures/multi_fix4_gap10.jpg'), hasLength(4));
  });

  group('one plate alone is one plate', () {
    test('store photo (dense colonies on a bright agar)', () {
      _expectPlates(_find('../store/video/plate.jpg'), [
        (cx: 600, cy: 500, r: 420),
      ]);
    });
    for (final name in ['sparse', 'medium', 'dense', 'backlit', 'empty']) {
      test('$name.jpg', () {
        _expectPlates(_find('test/fixtures/$name.jpg'), [
          (cx: 500, cy: 500, r: 420),
        ]);
      });
    }
  });

  test('the manual\'s photo of four plates', () {
    final found = _find('test/manual/multi_plates.jpg');
    expect(found, hasLength(4));
    final r = [for (final p in found) p.radius];
    expect(r.reduce(math.min) / r.reduce(math.max), greaterThan(0.9));
  });

  test('plates of a drawn photo on a light surround', () {
    final plates = [
      SynthPlate(260, 250, 200, colonies: 60),
      SynthPlate(690, 260, 205, colonies: 5),
    ];
    final bytes = synthPhoto(960, 520, plates, seed: 3);
    final light = img.decodeJpg(bytes)!;
    // Swap the surround to near white (keep the dishes).
    for (final p in light) {
      final inside = plates.any(
        (s) =>
            math.pow(p.x - s.cx, 2) + math.pow(p.y - s.cy, 2) <
            math.pow(s.radius + 3, 2),
      );
      if (!inside) {
        p
          ..r = 225
          ..g = 225
          ..b = 220;
      }
    }
    final found = findPlatesInPhoto((img.encodeJpg(light), PlateFormat.dish90))
        .plates;
    _expectPlates(found, [
      for (final s in plates) (cx: s.cx, cy: s.cy, r: s.radius),
    ]);
  });

  test('a photo without a dish finds none, and keeps its size', () {
    final blank = img.Image(width: 640, height: 480)
      ..clear(img.ColorRgb8(30, 30, 34));
    final found = findPlatesInPhoto((img.encodeJpg(blank), PlateFormat.dish90));
    expect(found.plates, isEmpty);
    expect((found.width, found.height), (640, 480));
    expect(found.otherSizes, isFalse);
  });

  test('small dishes: r100 in a 1200 × 900 photo', () {
    // A tenth of the short side (90 px): one plate alone, and five.
    final one = [SynthPlate(600, 450, 100, colonies: 20)];
    _expectPlates(
      findPlatesInPhoto((
        synthPhoto(1200, 900, one, seed: 2),
        PlateFormat.dish90,
      )).plates,
      [for (final s in one) (cx: s.cx, cy: s.cy, r: s.radius)],
    );
    final five = [
      SynthPlate(200, 200, 100, colonies: 20),
      SynthPlate(500, 200, 100, colonies: 40),
      SynthPlate(800, 200, 100, colonies: 5),
      SynthPlate(300, 600, 100, colonies: 60),
      SynthPlate(700, 600, 100, colonies: 10),
    ];
    _expectPlates(
      findPlatesInPhoto((
        synthPhoto(1200, 900, five, seed: 3),
        PlateFormat.dish90,
      )).plates,
      [for (final s in five) (cx: s.cx, cy: s.cy, r: s.radius)],
    );
  });

  test('a dish of another size is left out, and said so', () {
    final found = findPlatesInPhoto((
      synthPhoto(1200, 800, [
        SynthPlate(350, 400, 300, colonies: 30),
        SynthPlate(900, 400, 180, colonies: 20),
      ], seed: 4),
      PlateFormat.dish90,
    ));
    _expectPlates(found.plates, [(cx: 350, cy: 400, r: 300)]);
    expect(found.otherSizes, isTrue);
    // Plates of one size, or colonies inside a dish, are not another size.
    for (final f in [
      'test/fixtures/multi_six_gap10.jpg',
      'test/fixtures/medium.jpg',
      '../store/video/plate.jpg',
    ]) {
      final bytes = File(f).readAsBytesSync();
      expect(
        findPlatesInPhoto((bytes, PlateFormat.dish90)).otherSizes,
        isFalse,
        reason: f,
      );
    }
  });

  group('found-plates screen', () {
    Future<void> open(
      WidgetTester tester,
      Uint8List photo,
      String until,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final store = PlateStore(MemoryStorage());
      await tester.runAsync(store.load);
      await tester.pumpWidget(
        MaterialApp(
          home: MultiPlateScreen(store: store, photo: photo),
        ),
      );
      for (var i = 0; i < 100 && find.text(until).evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }
    }

    testWidgets('no plate found: the photo, a message and the pencil', (
      tester,
    ) async {
      final blank = img.Image(width: 640, height: 480)
        ..clear(img.ColorRgb8(30, 30, 34));
      await open(tester, img.encodeJpg(blank), tr.multiNoPlatesFound);
      expect(find.text(tr.multiNoPlatesFound), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      final photo = find.byType(Image);
      expect(photo, findsOneWidget);
      // Mark a plate by hand.
      await tester.tap(find.byTooltip(tr.multiAddRemove));
      await tester.pump();
      await tester.tapAt(tester.getCenter(photo));
      await tester.pump();
      await tester.tap(find.byTooltip(tr.multiDone));
      await tester.pump();
      expect(find.text(tr.multiPlatesFound(1)), findsOneWidget);
      expect(find.text(tr.multiTapToCount(1)), findsOneWidget);
    });

    testWidgets('a dish of another size: a note to add it by hand', (
      tester,
    ) async {
      final photo = synthPhoto(1200, 800, [
        SynthPlate(350, 400, 300, colonies: 30),
        SynthPlate(900, 400, 180, colonies: 20),
      ], seed: 4);
      await open(tester, photo, tr.multiPlatesFound(1));
      expect(find.text(tr.multiPlatesFound(1)), findsOneWidget);
      expect(find.text(tr.multiOtherSizes), findsOneWidget);
    });
  });
}
