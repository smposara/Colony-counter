import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:colony_counter/core/calculator.dart';
import 'package:colony_counter/core/normalize.dart';
import 'package:colony_counter/core/pipeline.dart';
import 'package:flutter_test/flutter_test.dart';

/// Golden plates rendered by ml/colonycounter/synth.py. Each JSON holds the true
/// colony positions and the Python reference pipeline's count on the same JPEG.
const fixtures = ['empty', 'sparse', 'medium', 'dense', 'backlit'];

void main() {
  group('pipeline on golden plates', () {
    for (final name in fixtures) {
      test(name, () {
        final bytes = File('test/fixtures/$name.jpg').readAsBytesSync();
        final label = jsonDecode(
          File('test/fixtures/$name.json').readAsStringSync(),
        ) as Map<String, dynamic>;
        final truth = label['true_count'] as int;
        final python = label['python_count'] as int;
        final plate = label['plate'] as Map<String, dynamic>;

        final res = countPhoto(bytes);

        final r = (plate['radius'] as num).toDouble();
        expect((res.plate.cx - (plate['cx'] as num)).abs(), lessThan(0.02 * r));
        expect((res.plate.cy - (plate['cy'] as num)).abs(), lessThan(0.02 * r));
        expect((res.plate.radius - r).abs(), lessThan(0.03 * r));

        expect(res.polarity.name, label['polarity']);
        // Accuracy against ground truth...
        expect(
          (res.count - truth).abs(),
          lessThanOrEqualTo(math.max(3, 0.08 * truth)),
          reason: 'Dart ${res.count} vs truth $truth',
        );
        // ...and agreement with the Python reference implementation.
        expect(
          (res.count - python).abs(),
          lessThanOrEqualTo(math.max(3, 0.05 * python)),
          reason: 'Dart ${res.count} vs Python $python',
        );
      });
    }
  });

  test('forced polarity and fixed plate are honoured', () {
    final bytes = File('test/fixtures/sparse.jpg').readAsBytesSync();
    final first = countPhoto(bytes);
    final again = countPhoto(
      bytes,
      CountOptions(plate: first.plate, polarity: Polarity.bright),
    );
    expect(again.plate.cx, closeTo(first.plate.cx, 1e-6));
    expect(again.count, first.count);
  });

  group('calculator', () {
    test('single plate', () {
      expect(cfuPerMl(150, 1e-4, 0.1), closeTo(1.5e7, 1));
    });

    test('ISO 7218 two successive dilutions', () {
      final e = estimate([
        const PlateCount(168, 1e-2, volumeMl: 1),
        const PlateCount(14, 1e-3, volumeMl: 1),
      ], rule: CountingRule.iso7218);
      expect(e.value, roundSig(182 / (1.1 * 1e-2)));
      expect(e.qualifier, Qualifier.exact);
      expect(e.platesUsed.length, 2);
    });

    test('BAM duplicates pooled', () {
      final e = estimate(const [
        PlateCount(232, 1e-2),
        PlateCount(244, 1e-2),
        PlateCount(33, 1e-3),
        PlateCount(28, 1e-3),
      ]);
      expect(e.value, roundSig(537 / (0.1 * (2e-2 + 2e-3))));
    });

    test('below range uses least diluted plate', () {
      final e = estimate(const [PlateCount(12, 1e-1), PlateCount(1, 1e-2)]);
      expect(e.qualifier, Qualifier.estimated);
      expect(e.value, 1200);
    });

    test('zero colonies reports less-than', () {
      final e = estimate(const [PlateCount(0, 1e-1)]);
      expect(e.qualifier, Qualifier.lessThan);
      expect(e.value, 100);
    });

    test('TNTC reports greater-than', () {
      final e = estimate(const [
        PlateCount(300, 1e-3, tntc: true),
        PlateCount(300, 1e-4, tntc: true),
      ]);
      expect(e.qualifier, Qualifier.greaterThan);
      expect(e.value, 3e7);
    });

    test('spreaders excluded', () {
      final e = estimate(const [
        PlateCount(100, 1e-3, spreader: true),
        PlateCount(40, 1e-3),
      ]);
      expect(e.platesUsed.single.count, 40);
      expect(
        estimate(const [PlateCount(1, 1e-3, spreader: true)]).value.isNaN,
        isTrue,
      );
    });

    test('formatting', () {
      expect(roundSig(16545), 17000);
      expect(formatSci(16545), '1.7 × 10^4');
      expect(formatSci(99600), '1.0 × 10^5');
    });
  });
}
