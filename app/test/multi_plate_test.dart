// The multi-plate finder ("several plates in one photo") on composited
// photos with known plates (made by ml/scripts/make_multi_plate_cases.py:
// fixture dishes laid out 10 px to 150 px apart, faint rims, mixed colony
// densities, dark and light surrounds) and on single plates, which must come
// out as one plate, never as clusters of colonies.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:colony_counter/core/pipeline.dart';
import 'package:colony_counter/core/plate.dart';
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

  test('a photo without a dish finds none', () {
    final blank = img.Image(width: 640, height: 480)
      ..clear(img.ColorRgb8(30, 30, 34));
    expect(
      () => findPlatesInPhoto((img.encodeJpg(blank), PlateFormat.dish90)),
      throwsStateError,
    );
  });
}
