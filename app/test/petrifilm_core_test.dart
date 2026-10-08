import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:colony_counter/core/petrifilm.dart';
import 'package:flutter_test/flutter_test.dart';

// Golden dry films from ml/scripts/make_app_fixtures.py --petrifilm: true
// counts and the Python reference result on the same JPEG.
const filmFixtures = [
  'film_ac',
  'film_ec',
  'film_cc',
  'film_eb',
  'film_ym',
  'film_ac_crowded',
];

Map<String, dynamic> _label(String name) =>
    jsonDecode(File('test/fixtures/$name.json').readAsStringSync())
        as Map<String, dynamic>;

FilmResult _count(String name, Map<String, dynamic> label) =>
    countPetrifilmInPhoto((
      File('test/fixtures/$name.jpg').readAsBytesSync(),
      label['type'] as String,
    ));

double _num(dynamic v) => (v as num).toDouble();

void main() {
  group('Petrifilm counter on golden films', () {
    for (final name in filmFixtures) {
      test(name, () {
        final label = _label(name);
        final python = label['python'] as Map<String, dynamic>;
        final res = _count(name, label);

        // Grid: 1 cm squares at the film's scale and turn.
        final truePitch = 10 * _num(label['px_per_mm']);
        expect(res.grid.pitchPx, closeTo(truePitch, truePitch * 0.003));
        expect(res.grid.pitchPx, closeTo(_num(python['pitch_px']), 0.2));
        expect(res.grid.angleDeg, closeTo(_num(python['angle_deg']), 0.05));
        expect(res.grid.lineHalfPx, closeTo(_num(python['line_half_px']), 0.5));
        expect(res.grid.strength, closeTo(_num(python['grid_strength']), 0.03));
        expect(res.grid.strength, greaterThan(kGridMinStrength));

        // Growth area. On the crowded film both find the edge of the colony
        // band: synthetic films keep colonies 1.5 mm inside the rim.
        final area = label['area'] as Map<String, dynamic>;
        final pyArea = python['area'] as Map<String, dynamic>;
        final crowded = name.contains('crowded');
        expect(res.plate.cx, closeTo(_num(area['cx']), 2));
        expect(res.plate.cy, closeTo(_num(area['cy']), 2));
        expect(
          res.plate.radius,
          closeTo(
            _num(area['radius']),
            _num(area['radius']) * (crowded ? 0.07 : 0.01),
          ),
        );
        expect(res.plate.cx, closeTo(_num(pyArea['cx']), 1));
        expect(res.plate.cy, closeTo(_num(pyArea['cy']), 1));
        expect(res.plate.radius, closeTo(_num(pyArea['radius']), 1));

        // Counts against the truth and the Python reference.
        final truth = (label['true'] as Map).cast<String, num>();
        final pyCounts = (python['counts'] as Map).cast<String, num>();
        final pyEstimates = (python['estimates'] as Map?)?.cast<String, num>();
        expect(res.flags, python['flags']);
        expect(res.estimates != null, pyEstimates != null);
        for (final k in truth.keys) {
          final t = truth[k]!.toDouble();
          if (pyEstimates != null) {
            expect(
              res.estimates![k]!,
              closeTo(t, t * 0.15),
              reason: '$k estimate',
            );
            expect(
              res.estimates![k]!,
              closeTo(pyEstimates[k]!.toDouble(), t * 0.05),
              reason: '$k estimate vs Python',
            );
            continue;
          }
          final got = res.counts[k]!.toDouble();
          expect(
            got,
            closeTo(t, math.max(2, t * 0.06)),
            reason: '$k: Dart $got vs truth $t',
          );
          expect(
            got,
            closeTo(pyCounts[k]!.toDouble(), math.max(1, t * 0.03)),
            reason: '$k: Dart $got vs Python ${pyCounts[k]}',
          );
        }

        // Marks agree with Python's one by one (position and kind).
        final pyCols = (python['colonies'] as List)
            .cast<Map<String, dynamic>>();
        var matched = 0;
        for (final p in pyCols) {
          if (res.colonies.any(
            (c) =>
                c.kind == p['kind'] &&
                c.gas == p['gas'] &&
                c.yellow == p['yellow'] &&
                math.sqrt(
                      math.pow(c.x - _num(p['x']), 2) +
                          math.pow(c.y - _num(p['y']), 2),
                    ) <=
                    2,
          )) {
            matched++;
          }
        }
        expect(
          matched / math.max(1, pyCols.length),
          greaterThanOrEqualTo(0.9),
          reason: '$matched of ${pyCols.length} Python marks matched',
        );
      });
    }
  });

  // Dish photos counted as films: no printed grid, so the count is flagged
  // (or no growth area is found at all), and nothing crashes.
  for (final name in ['sparse', 'medium', 'drops', 'zones_reflected']) {
    test('no grid on a dish photo: $name', () {
      final bytes = File('test/fixtures/$name.jpg').readAsBytesSync();
      try {
        final res = countPetrifilmInPhoto((bytes, 'ac'));
        expect(res.flags, contains('grid_not_found'));
        expect(res.grid.pitchPx, greaterThan(0));
      } on StateError {
        // "No growth area found" is also an acceptable outcome.
      }
    });
  }

  test('film types', () {
    expect(kFilmTypes.keys, ['ac', 'ec', 'cc', 'eb', 'ym']);
    expect(kFilmTypes['ec']!.results, ['ecoli', 'coliform']);
    expect(kFilmTypes['ac']!.confirmed, isTrue);
    for (final t in kFilmTypes.values) {
      expect(t.countMin, lessThan(t.countMax));
      expect(t.areaCm2, 20);
    }
  });

  test('grid maps image and grid frames both ways', () {
    const g = FilmGrid(120, 7.5, 3, 11, 500, 400);
    final (gx, gy) = g.toGrid(123.4, 567.8);
    final (x, y) = g.toImage(gx, gy);
    expect(x, closeTo(123.4, 1e-9));
    expect(y, closeTo(567.8, 1e-9));
    expect(g.mmPerPx, closeTo(1 / 12, 1e-12));
  });
}
