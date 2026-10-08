import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:colony_counter/core/drop_layout.dart';
import 'package:colony_counter/core/drop_stats.dart';
import 'package:colony_counter/core/plate.dart';
import 'package:flutter_test/flutter_test.dart';

// Golden drop plates from ml/scripts/make_app_fixtures.py --drops: the true
// drops and the Python reference result on the same JPEG.
const dropFixtures = [
  'drops_sectors8',
  'drops_sectors6x2',
  'drops_grid4x3',
  'drops_grid5x5',
  'drops_sparse',
];

Map<String, dynamic> _label(String name) =>
    jsonDecode(File('test/fixtures/$name.json').readAsStringSync())
        as Map<String, dynamic>;

double _num(dynamic v) => (v as num).toDouble();

DropTemplate _template(Map<String, dynamic> j) => switch (j['kind']) {
  'sectors' => SectorTemplate(
    n: j['n'] as int,
    ringMm: _num(j['ring_mm']),
    dropsPerDilution: j['drops_per_dilution'] as int,
  ),
  'grid' => GridTemplate(
    rows: j['rows'] as int,
    cols: j['cols'] as int,
    pitchMm: _num(j['pitch_mm']),
  ),
  _ => const FreeTemplate(),
};

DropPlateResult _count(String name, Map<String, dynamic> label) =>
    countDropPlateInPhoto((
      File('test/fixtures/$name.jpg').readAsBytesSync(),
      _template(label['layout'] as Map<String, dynamic>),
      [for (final d in label['dilutions'] as List) d as int],
      _num(label['volume_ul']),
      PlateFormat.dish90,
      null,
    ));

FoundDrop _nearest(List<FoundDrop> drops, double x, double y) => drops.reduce(
  (a, b) =>
      math.pow(a.x - x, 2) + math.pow(a.y - y, 2) <=
          math.pow(b.x - x, 2) + math.pow(b.y - y, 2)
      ? a
      : b,
);

List<DropCount> _counts(List<(int, List<int>)> rows) => [
  for (final (d, cs) in rows)
    for (var i = 0; i < cs.length; i++) DropCount(d, i + 1, cs[i]),
];

void main() {
  group('Drop plates on golden fixtures', () {
    for (final name in dropFixtures) {
      test(name, () {
        final label = _label(name);
        final py = label['python'] as Map<String, dynamic>;
        final res = _count(name, label);
        final pxPerMm = _num(label['px_per_mm']);

        // Every planned drop, where Python and the truth put it, with the
        // same dilution.
        final pyDrops = [
          for (final d in py['drops'] as List) d as Map<String, dynamic>,
        ];
        expect(res.drops, hasLength(pyDrops.length));
        for (final p in pyDrops) {
          final d = _nearest(res.drops, _num(p['x']), _num(p['y']));
          final off = math.sqrt(
            math.pow(d.x - _num(p['x']), 2) + math.pow(d.y - _num(p['y']), 2),
          );
          expect(off / pxPerMm, lessThan(1.0), reason: 'drop $p');
          expect(d.dilutionExp, p['dilution_exp'], reason: 'drop $p');
          expect(d.confluent, p['confluent'], reason: 'drop $p');
          if (!d.confluent) {
            final c = p['count'] as int;
            expect(
              d.count,
              closeTo(c, math.max(2, 0.1 * c)),
              reason: 'drop $p',
            );
          }
        }
        for (final t in label['true_drops'] as List) {
          final d = _nearest(res.drops, _num(t['x']), _num(t['y']));
          final off = math.sqrt(
            math.pow(d.x - _num(t['x']), 2) + math.pow(d.y - _num(t['y']), 2),
          );
          expect(off / pxPerMm, lessThan(2.8));
          expect(d.dilutionExp, t['dilution_exp']);
        }
        if (py['rotation_deg'] != null) {
          // The same placement can be reached a symmetry step round (one
          // sector, or half / a quarter turn of a grid), with the labels
          // following.
          final layout = label['layout'] as Map<String, dynamic>;
          final step = layout['kind'] == 'sectors'
              ? 360 / (layout['n'] as int)
              : layout['rows'] == layout['cols']
              ? 90.0
              : 180.0;
          final dr = (res.fit!.rotationDeg - _num(py['rotation_deg'])) % step;
          expect(math.min(dr, step - dr), lessThan(1.5));
          expect(res.fit!.scale, closeTo(_num(py['scale']), 0.02));
        }
        expect(res.flags, py['flags']);

        // Replicates are 1..n within each dilution.
        for (final dil in {for (final d in res.drops) d.dilutionExp}) {
          final reps = [
            for (final d in res.drops)
              if (d.dilutionExp == dil) d.replicate,
          ]..sort();
          expect(reps, List.generate(reps.length, (i) => i + 1));
        }

        // CFU/mL close to Python's and to the estimate from the true counts.
        final rows = dilutionTable(res.counts);
        for (final mode in DropMode.values) {
          final e = estimateDrops(rows, _num(label['volume_ul']), mode: mode);
          final pe = py[mode.name] as Map<String, dynamic>;
          expect(e.qualifier, pe['qualifier']);
          expect(
            e.cfuPerMl,
            closeTo(_num(pe['cfu_per_ml']), 0.1 * _num(pe['cfu_per_ml'])),
          );
        }
        final truth = _num(
          (label['true_estimate'] as Map<String, dynamic>)['cfu_per_ml'],
        );
        final pooled = estimateDrops(rows, _num(label['volume_ul']));
        expect(pooled.cfuPerMl, closeTo(truth, 0.15 * truth));
      });
    }

    test('statistics agree with Python on the same counts', () {
      for (final name in dropFixtures) {
        final py = _label(name)['python'] as Map<String, dynamic>;
        final drops = <DropCount>[];
        for (final r in py['table'] as List) {
          final d = r['dilution_exp'] as int;
          final cs = (r['counts'] as List).cast<int>();
          for (var i = 0; i < cs.length; i++) {
            drops.add(DropCount(d, i + 1, cs[i]));
          }
          for (var i = 0; i < (r['tntc'] as int); i++) {
            drops.add(DropCount(d, cs.length + i + 1, 0, tntc: true));
          }
        }
        final rows = dilutionTable(drops);
        final pyRows = py['table'] as List;
        expect(rows, hasLength(pyRows.length));
        for (var i = 0; i < rows.length; i++) {
          final p = pyRows[i] as Map<String, dynamic>;
          expect(rows[i].mean, closeTo(_num(p['mean']), 1e-12));
          expect(rows[i].vmr, closeTo(_num(p['vmr']), 1e-12));
          expect(rows[i].chi2, closeTo(_num(p['chi2']), 1e-12));
          expect(rows[i].p, closeTo(_num(p['p']), 1e-9));
          expect(rows[i].flags, p['flags']);
        }
        for (final mode in DropMode.values) {
          final e = estimateDrops(rows, 10, mode: mode);
          final pe = py[mode.name] as Map<String, dynamic>;
          expect(e.qualifier, pe['qualifier']);
          expect(
            e.cfuPerMl,
            closeTo(_num(pe['cfu_per_ml']), 1e-6 * _num(pe['cfu_per_ml'])),
          );
          expect(
            e.low,
            closeTo(_num(pe['low']), 1e-6 * _num(pe['low']) + 1e-9),
          );
          expect(e.high, closeTo(_num(pe['high']), 1e-6 * _num(pe['high'])));
          expect(e.dilutionsUsed, pe['dilutions_used']);
          expect(e.dropsUsed, pe['drops_used']);
        }
      }
    });
  });

  group('Templates', () {
    test('drop diameter scales with volume', () {
      expect(dropDiameterMm(10), closeTo(7.0, 1e-12));
      expect(dropDiameterMm(80), closeTo(14.0, 1e-12));
    });

    test('sector positions run clockwise from the top', () {
      final pos = templatePositionsMm(
        const SectorTemplate(n: 8, ringMm: 25),
        List.generate(8, (i) => i + 3),
      );
      expect(pos, hasLength(8));
      expect([
        for (final p in pos) p.dilutionExp,
      ], List.generate(8, (i) => i + 3));
      expect(pos[0].x, closeTo(0, 1e-9));
      expect(pos[0].y, closeTo(-25, 1e-9));
      expect(pos[2].x, closeTo(25, 1e-9));
      expect(pos[2].y, closeTo(0, 1e-9));
    });

    test('grid: a row per dilution, a column per replicate', () {
      final pos = templatePositionsMm(
        const GridTemplate(rows: 4, cols: 3, pitchMm: 12),
        [4, 5, 6, 7],
      );
      expect(
        [for (final p in pos) p.dilutionExp],
        [4, 4, 4, 5, 5, 5, 6, 6, 6, 7, 7, 7],
      );
      expect([for (final p in pos.take(3)) p.replicate], [1, 2, 3]);
      expect(pos.first.x, closeTo(-12, 1e-9));
      expect(pos.first.y, closeTo(-18, 1e-9));
    });
  });

  group('Drop statistics', () {
    test('dilution table by hand', () {
      final r = dilutionTable(
        _counts([
          (5, [10, 12, 14]),
          (6, [1, 2, 0]),
        ]),
      ).first;
      expect(r.mean, closeTo(12, 1e-12));
      expect(r.sd, closeTo(2, 1e-12));
      expect(r.vmr, closeTo(4 / 12, 1e-12));
      expect(r.chi2, closeTo(8 / 12, 1e-12));
      // χ² sf(2/3, 2) = exp(−1/3).
      expect(r.p, closeTo(math.exp(-1 / 3), 1e-12));
      expect(r.flags, isEmpty);
    });

    test('overdispersed and outlier', () {
      final r = dilutionTable(
        _counts([
          (5, [20, 21, 19, 20, 60]),
        ]),
      ).first;
      expect(r.flags, containsAll(['overdispersed', 'outlier_drop']));
      expect(r.outliers, [4]);
    });

    test('tenfold check', () {
      var rows = dilutionTable(
        _counts([
          (5, [20, 22, 18]),
          (6, [15, 14, 16]),
        ]),
      );
      expect(rows.first.flags, contains('not_tenfold'));
      rows = dilutionTable(
        _counts([
          (5, [20, 22, 18]),
          (6, [2, 3, 1]),
        ]),
      );
      expect(rows.first.flags, isNot(contains('not_tenfold')));
    });

    test('TNTC and excluded drops are left out', () {
      final r = dilutionTable(const [
        DropCount(4, 1, 0, tntc: true),
        DropCount(4, 2, 99, excluded: true),
        DropCount(4, 3, 25),
      ]).first;
      expect(r.counts, [25]);
      expect(r.tntc, 1);
      expect(r.excluded, 1);
    });

    test('first countable dilution and pooled', () {
      final rows = dilutionTable(
        _counts([
          (4, [40, 45, 38]),
          (5, [20, 25, 15]),
          (6, [3, 2, 1]),
        ]),
      );
      final first = estimateDrops(rows, 10, mode: DropMode.first);
      expect(first.qualifier, 'exact');
      expect(first.dilutionsUsed, [5]);
      expect(first.cfuPerMl, closeTo(2e8, 1));
      final pooled = estimateDrops(rows, 10);
      expect(pooled.cfuPerMl, closeTo(63 / (3 * 0.01e-5 + 0.01e-6), 1));
      expect(pooled.dilutionsUsed, [5, 6]);
      expect(pooled.low, lessThan(pooled.cfuPerMl));
      expect(pooled.high, greaterThan(pooled.cfuPerMl));
    });

    test('Garwood interval', () {
      final (lo, hi) = poissonInterval(10);
      expect(lo, closeTo(4.7954, 1e-3));
      expect(hi, closeTo(18.3904, 1e-3));
      final (lo0, hi0) = poissonInterval(0);
      expect(lo0, 0);
      expect(hi0, closeTo(3.6889, 1e-3));
    });

    test('detection limit when nothing grew', () {
      final e = estimateDrops(
        dilutionTable(
          _counts([
            (2, [0, 0, 0, 0, 0]),
            (3, [0, 0, 0, 0, 0]),
          ]),
        ),
        10,
      );
      expect(e.qualifier, '<');
      expect(e.cfuPerMl, closeTo(2000, 1e-9)); // 1 / (5 × 0.01 mL × 10⁻²)
    });

    test('below and above the window', () {
      var e = estimateDrops(
        dilutionTable(
          _counts([
            (2, [1, 2, 0]),
          ]),
        ),
        10,
      );
      expect(e.qualifier, 'estimated');
      expect(e.note, contains('below'));
      e = estimateDrops(
        dilutionTable(const [
          DropCount(3, 1, 0, tntc: true),
          DropCount(3, 2, 0, tntc: true),
          DropCount(4, 1, 0, tntc: true),
          DropCount(4, 2, 0, tntc: true),
        ]),
        10,
      );
      expect(e.qualifier, '>');
      expect(e.cfuPerMl, closeTo(30 * 2 / (2 * 0.01e-4), 1e-3));
    });

    test('a series straddling the window uses the closest dilution', () {
      for (final mode in DropMode.values) {
        final e = estimateDrops(
          dilutionTable(
            _counts([
              (5, [40, 45, 38]),
              (6, [2, 1, 2]),
            ]),
          ),
          10,
          mode: mode,
        );
        expect(e.qualifier, 'estimated');
        expect(e.dilutionsUsed, [5]);
        expect(e.note, startsWith('no dilution in the counting window'));
        expect(e.cfuPerMl, closeTo(123 / (3 * 0.01e-5), 1));
      }
      final above = estimateDrops(
        dilutionTable(
          _counts([
            (5, [35, 36, 37]),
            (6, [1, 0, 1]),
          ]),
        ),
        10,
      );
      expect(above.dilutionsUsed, [5]);
      final below = estimateDrops(
        dilutionTable(
          _counts([
            (5, [60, 65, 58]),
            (6, [2, 1, 2]),
          ]),
        ),
        10,
      );
      expect(below.dilutionsUsed, [6]);
    });

    test('χ² tail and gamma function', () {
      expect(logGamma(5), closeTo(math.log(24), 1e-12));
      expect(chi2Sf(3.841458820694124, 1), closeTo(0.05, 1e-10));
      expect(chi2Sf(30, 10), closeTo(8.56641210775301e-4, 1e-12));
    });
  });
}
