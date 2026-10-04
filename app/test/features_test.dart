import 'dart:math' as math;

import 'package:colony_counter/core/calculator.dart';
import 'package:colony_counter/core/classical.dart';
import 'package:colony_counter/core/colour.dart';
import 'package:colony_counter/core/spots.dart';
import 'package:colony_counter/core/stats.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('replicate statistics', () {
    test('mean, SD, CV and log10 of replicate CFU/mL', () {
      final s = ReplicateStats([1e6, 2e6, 4e6]);
      expect(s.n, 3);
      expect(s.mean, closeTo(7e6 / 3, 1));
      expect(s.sd, closeTo(1527525.2, 1));
      expect(s.cvPercent, closeTo(65.47, 0.01));
      expect(s.log10Mean, closeTo(6 + math.log(2) / math.ln10, 1e-9));
      expect(s.log10Sd, closeTo(math.log(2) / math.ln10, 1e-9));
    });

    test('each replicate pools its own dilutions', () {
      final obs = [
        const Observation(PlateCount(120, 1e-4), 1),
        const Observation(PlateCount(14, 1e-5), 1), // out of range, ignored
        const Observation(PlateCount(80, 1e-4), 2),
        const Observation(PlateCount(30, 1e-5), 2),
      ];
      final r = analyseReplicates(obs, CountingRule.fdaBam);
      expect(r.perReplicate.keys, [1, 2]);
      expect(r.perReplicate[1]!.value, roundSig(120 / (0.1 * 1e-4)));
      expect(r.perReplicate[2]!.value, roundSig(110 / (0.1 * (1e-4 + 1e-5))));
      expect(r.stats.n, 2);
      expect(r.qualified, isFalse);
    });

    test('drop plates use the 3–30 range with the drop volume', () {
      final obs = [
        for (final c in [12, 15, 9])
          Observation(PlateCount(c, 1e-5, volumeMl: 0.01), 1),
        const Observation(PlateCount(45, 1e-4, volumeMl: 0.01), 1), // above 30
      ];
      final r = analyseReplicates(obs, CountingRule.dropPlate);
      expect(r.perReplicate[1]!.value, roundSig(36 / (3 * 0.01 * 1e-5)));
    });

    test('log reduction and percent kill', () {
      final red = Reduction(
        ReplicateStats([1e8, 1e8]),
        ReplicateStats([1e5, 1e5]),
      );
      expect(red.logReduction, closeTo(3, 1e-9));
      expect(red.percentKill, closeTo(99.9, 1e-9));
      expect(red.logReductionSd, closeTo(0, 1e-9));
    });
  });

  group('colour classes', () {
    test('Lab conversion of reference colours', () {
      final white = rgbToLab(255, 255, 255);
      expect(white.l, closeTo(100, 0.1));
      expect(white.a.abs(), lessThan(0.5));
      final blue = rgbToLab(0, 0, 255);
      expect(blue.b, lessThan(-100));
    });

    test('blue/white screening separates blue colonies', () {
      final whites = List.generate(20, (i) => rgbToLab(235 - i, 228, 205));
      final blues = List.generate(6, (i) => rgbToLab(70 + i, 110, 190));
      final cls = classifyColours([...whites, ...blues], ColourMode.blueWhite);
      expect(cls.take(20).every((c) => c == 0), isTrue);
      expect(cls.skip(20).every((c) => c == 1), isTrue);
    });

    test('a plate of only white colonies has no blue', () {
      final whites = List.generate(
        30,
        (i) => rgbToLab(230 - i % 5, 225, 200 + i % 3),
      );
      expect(
        classifyColours(whites, ColourMode.blueWhite).every((c) => c == 0),
        isTrue,
      );
    });

    test('two colours: minority becomes class 1; one colour stays class 0', () {
      final pink = List.generate(5, (_) => rgbToLab(220, 90, 140));
      final cream = List.generate(15, (_) => rgbToLab(230, 220, 190));
      final cls = classifyColours([...cream, ...pink], ColourMode.twoColours);
      expect(cls.where((c) => c == 1).length, 5);
      expect(
        classifyColours(cream, ColourMode.twoColours).every((c) => c == 0),
        isTrue,
      );
    });
  });

  group('drop-plate spots', () {
    const mmPerPx = 0.05; // 20 px per mm
    List<Colony> drop(double cx, double cy, int n, int seed) {
      final rnd = math.Random(seed);
      return [
        for (var i = 0; i < n; i++)
          Colony(
            cx + (rnd.nextDouble() - 0.5) * 100,
            cy + (rnd.nextDouble() - 0.5) * 100,
            6,
          ),
      ];
    }

    test('groups colonies into drops in reading order', () {
      final colonies = [
        ...drop(1200, 400, 8, 1), // top right
        ...drop(400, 400, 12, 2), // top left
        ...drop(400, 1000, 5, 3), // bottom left
      ];
      final spots = suggestSpots(colonies, mmPerPx);
      expect(spots.length, 3);
      expect(spots[0].cx, closeTo(400, 40));
      expect(spots[1].cx, closeTo(1200, 40));
      expect(spots[2].cy, closeTo(1000, 40));
      expect(countInSpot(spots[0], colonies), 12);
      expect(countInSpot(spots[1], colonies), 8);
      expect(countInSpot(spots[2], colonies), 5);
      // At least the 7 mm drop size.
      expect(spots.every((s) => s.radius >= 3.5 / mmPerPx - 1e-9), isTrue);
    });

    test('spot JSON round trip', () {
      const s = Spot(1, 2, 3, dilutionExp: 5, replicate: 2, tntc: true);
      final b = Spot.fromJson(s.toJson());
      expect(
        [b.cx, b.cy, b.radius, b.dilutionExp, b.replicate, b.tntc],
        [1, 2, 3, 5, 2, true],
      );
    });
  });

  test('colony colour and class survive JSON', () {
    final c = Colony(1, 2, 3, colour: const Lab(80, -2, -30), cls: 1);
    final b = Colony.fromJson(c.toJson());
    expect(b.cls, 1);
    expect(b.colour!.b, -30);
  });
}
