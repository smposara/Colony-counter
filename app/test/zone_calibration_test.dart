import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:colony_counter/core/zone_calibration.dart';
import 'package:colony_counter/core/zones.dart';
import 'package:flutter_test/flutter_test.dart';

List<CalZone> _zones(
  List<double> diffs, {
  List<double>? sizes,
  List<double>? rf,
}) => [
  for (var i = 0; i < diffs.length; i++)
    CalZone(
      appMm: [(sizes?[i] ?? 8 + 3.0 * i) + diffs[i]],
      userMm: [sizes?[i] ?? 8 + 3.0 * i],
      radialFraction: rf?[i] ?? 0.3,
    ),
];

double? _num(Object? v) => (v as num?)?.toDouble();

void main() {
  group('Agreement summary', () {
    test('perfect agreement is good', () {
      final s = calibrationSummary(
        _zones(List.filled(6, 0)),
        appSpan: 60,
        userSpan: 60,
      );
      expect(s.n, 6);
      expect(s.bias, 0);
      expect(s.sd, 0);
      expect(s.verdict, CalibrationVerdict.good);
      expect(s.hint, CalibrationHint.none);
      expect(s.within1mm, 1);
    });

    test('bias and limits of agreement', () {
      const d = [0.3, 0.5, 0.4, 0.6, 0.2, 0.4];
      final s = calibrationSummary(_zones(d));
      final sd = math.sqrt(
        d.fold(0.0, (a, x) => a + (x - 0.4) * (x - 0.4)) / 5,
      );
      expect(s.bias, closeTo(0.4, 1e-12));
      expect(s.sd, closeTo(sd, 1e-12));
      expect(s.loaLow, closeTo(0.4 - 1.96 * sd, 1e-12));
      expect(s.loaHigh, closeTo(0.4 + 1.96 * sd, 1e-12));
      expect(s.maxAbs, closeTo(0.6, 1e-12));
    });

    test('a ruler needs more zones than a calliper', () {
      CalibrationVerdict v(
        int n, [
        CalibrationTool t = CalibrationTool.calliper,
      ]) => calibrationSummary(_zones(List.filled(n, 0.1)), tool: t).verdict;
      expect(v(5), CalibrationVerdict.tooFew);
      expect(v(6), CalibrationVerdict.good);
      expect(v(7, CalibrationTool.ruler), CalibrationVerdict.tooFew);
      expect(v(8, CalibrationTool.ruler), CalibrationVerdict.good);
    });

    test('excluded and unmeasured zones are left out', () {
      final s = calibrationSummary([
        ..._zones(List.filled(6, 0)),
        const CalZone(appMm: [double.nan], userMm: [12]),
        const CalZone(appMm: [20], userMm: [25], included: false),
      ]);
      expect(s.n, 6);
      expect(s.bias, 0);
    });

    test('a scale error shows as a slope', () {
      final s = calibrationSummary([
        for (final x in const [8.0, 12.0, 16.0, 20.0, 24.0, 28.0, 32.0])
          CalZone(appMm: [x * 1.05], userMm: [x]),
      ]);
      expect(s.slope, closeTo(0.05 / 1.025, 1e-9));
      expect(s.slopeSignificant, isTrue);
      expect(s.hint, CalibrationHint.scale);
    });

    test('the span alone flags the scale', () {
      final s = calibrationSummary(
        _zones(List.filled(6, 0.6)),
        appSpan: 63,
        userSpan: 60,
      );
      expect(s.scaleError, closeTo(0.05, 1e-12));
      expect(s.verdict, CalibrationVerdict.usable);
      expect(s.hint, CalibrationHint.scale);
    });

    test('zones of one size never suggest a scale error', () {
      final s = calibrationSummary(
        _zones(
          [0.0, 0.0, 0.1, 1.3, 1.2, 1.4],
          sizes: List.filled(6, 15),
          rf: [0.2, 0.3, 0.4, 0.8, 0.8, 0.9],
        ),
      );
      expect(s.slopeSignificant, isFalse);
      expect(s.edgeMinusCentre, closeTo(1.3 - 1 / 30, 1e-12));
      expect(s.hint, CalibrationHint.lens);
    });

    test('repeatability from several photos', () {
      final s = calibrationSummary(const [
        CalZone(appMm: [10, 10.2], userMm: [10]),
        CalZone(appMm: [20, 20.4], userMm: [20]),
      ]);
      expect(s.repeatabilitySd, closeTo(math.sqrt((0.02 + 0.08) / 2), 1e-12));
    });

    test('the farthest pair of disks and their span', () {
      const disks = [
        (100.0, 100.0, 30.0),
        (400.0, 100.0, 30.0),
        (300.0, 500.0, 30.0),
        (120.0, 130.0, 30.0),
      ];
      final (i, j) = farthestPair(disks);
      expect({i, j}, {0, 2});
      expect(appSpanMm(disks[0], disks[1], 0.1), closeTo(36, 1e-9));
    });
  });

  test('matches the Python reference on the shared cases', () {
    final cases = jsonDecode(
      File('test/fixtures/calibration_cases.json').readAsStringSync(),
    ) as List;
    expect(cases.length, greaterThanOrEqualTo(12));
    for (final c in cases.cast<Map<String, dynamic>>()) {
      final zones = [
        for (final z in (c['zones'] as List).cast<Map<String, dynamic>>())
          CalZone(
            appMm: [for (final v in z['app_mm'] as List) (v as num).toDouble()],
            userMm: [
              for (final v in z['user_mm'] as List) (v as num).toDouble(),
            ],
            radialFraction: (z['radial_fraction'] as num).toDouble(),
            included: z['included'] as bool,
          ),
      ];
      final s = calibrationSummary(
        zones,
        appSpan: _num(c['app_span']),
        userSpan: _num(c['user_span']),
        tool: CalibrationTool.values.byName(c['tool'] as String),
      );
      final py = c['python'] as Map<String, dynamic>;
      final name = c['name'] as String;
      expect(s.n, py['n'], reason: name);
      for (final (dart, key) in [
        (s.bias, 'bias'),
        (s.sd, 'sd'),
        (s.loaLow, 'loa_low'),
        (s.loaHigh, 'loa_high'),
        (s.maxAbs, 'max_abs'),
        (s.within1mm, 'within_1mm'),
        (s.slope, 'slope'),
        (s.edgeMinusCentre, 'edge_minus_centre'),
        (s.repeatabilitySd, 'repeatability_sd'),
        (s.scaleError, 'scale_error'),
      ]) {
        final want = _num(py[key]);
        if (want == null) {
          expect(dart, isNull, reason: '$name: $key');
        } else {
          expect(dart, closeTo(want, 1e-9), reason: '$name: $key');
        }
      }
      expect(s.slopeSignificant, py['slope_significant'], reason: name);
      const verdicts = {
        'good': CalibrationVerdict.good,
        'usable': CalibrationVerdict.usable,
        'poor': CalibrationVerdict.poor,
        'too_few': CalibrationVerdict.tooFew,
      };
      expect(s.verdict, verdicts[py['verdict']], reason: name);
      expect(
        s.hint,
        CalibrationHint.values.byName(py['hint'] as String),
        reason: name,
      );
    }
  });

  test(
    'end to end: the detector against simulated readings (truth + 0.4 mm)',
    () {
      final label = jsonDecode(
        File('test/fixtures/zones_reflected.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final res = measureZonesInPhoto((
        File('test/fixtures/zones_reflected.jpg').readAsBytesSync(),
        const ZoneOptions(),
      ));
      final truth = (label['true'] as List).cast<Map<String, dynamic>>();
      final plate = label['plate'] as Map<String, dynamic>;
      final trueMmPerPx =
          (label['plate_mm'] as num) / (2 * (plate['radius'] as num));
      Zone near(double x, double y) => res.zones.reduce(
        (a, b) =>
            math.pow(a.x - x, 2) + math.pow(a.y - y, 2) <=
                math.pow(b.x - x, 2) + math.pow(b.y - y, 2)
            ? a
            : b,
      );
      final zones = [
        for (final t in truth)
          () {
            final x = (t['x'] as num).toDouble(),
                y = (t['y'] as num).toDouble();
            final z = near(x, y);
            return CalZone(
              appMm: [z.diameterMm],
              userMm: [(t['diameter_mm'] as num).toDouble() + 0.4],
              radialFraction:
                  math.sqrt(
                    math.pow(x - res.plate.cx, 2) +
                        math.pow(y - res.plate.cy, 2),
                  ) /
                  res.plate.radius,
            );
          }(),
      ];
      final disks = [
        for (final t in truth)
          (
            (t['x'] as num).toDouble(),
            (t['y'] as num).toDouble(),
            3 / trueMmPerPx,
          ),
      ];
      final (i, j) = farthestPair(disks);
      final userSpan = appSpanMm(disks[i], disks[j], trueMmPerPx);
      final za = near(disks[i].$1, disks[i].$2),
          zb = near(disks[j].$1, disks[j].$2);
      final mmPerPx =
          res.zones.first.diameterMm / (2 * res.zones.first.radiusPx);
      final s = calibrationSummary(
        zones,
        appSpan: appSpanMm(
          (za.x, za.y, za.diskRadiusPx),
          (zb.x, zb.y, zb.diskRadiusPx),
          mmPerPx,
        ),
        userSpan: userSpan,
      );
      expect(s.n, 6);
      expect(s.bias, closeTo(-0.4, 0.25));
      expect(s.scaleError!.abs(), lessThan(0.01));
      expect(s.verdict, CalibrationVerdict.good);
    },
  );
}
