import 'dart:math' as math;

import 'package:colony_counter/core/classical.dart';
import 'package:colony_counter/core/plate.dart';
import 'package:colony_counter/core/timelapse.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('colonies are followed across rotated photos', () {
    final rnd = math.Random(7);
    const plate = Plate(500, 500, 450); // 0.1 mm/px
    // 40 colonies appearing at 16, 24 or 48 h, growing 0.05 mm/h.
    final truth = [
      for (var i = 0; i < 40; i++)
        () {
          final a = rnd.nextDouble() * 2 * math.pi,
              r = math.sqrt(rnd.nextDouble()) * 38;
          return (r * math.cos(a), r * math.sin(a), [16.0, 24.0, 48.0][i % 3]);
        }(),
    ];
    TimelapseFrame frame(double h, double angleDeg, bool mirror) {
      final c = math.cos(angleDeg * math.pi / 180),
          s = math.sin(angleDeg * math.pi / 180);
      return TimelapseFrame(h, plate, [
        for (final (x0, y, t) in truth)
          if (t <= h)
            () {
              final x = mirror ? -x0 : x0;
              final noise = (rnd.nextDouble() - 0.5) * 0.2;
              return Colony(
                plate.cx + (x * c - y * s) / 0.1 + noise,
                plate.cy + (x * s + y * c) / 0.1,
                (0.3 + 0.05 * (h - t)) / 2 / 0.1,
              );
            }(),
      ]);
    }

    final res = analyseTimelapse([
      frame(48, 0, false),
      frame(16, 63, false),
      frame(24, -120, true),
    ]);
    expect(res.frames.map((f) => f.hours), [16, 24, 48]);
    expect(res.tracks.length, 40);
    expect(res.newPerFrame, [14, 13, 13]);
    expect(res.medianGrowthMmPerH!, closeTo(0.05, 0.005));
    expect(res.alignments[1].mirrored, isTrue);
  });

  test('a single early colony keeps the orientation', () {
    const plate = Plate(500, 500, 450);
    final res = analyseTimelapse([
      TimelapseFrame(16, plate, const [Colony(600, 500, 3)]),
      TimelapseFrame(24, plate, const [
        Colony(600, 500, 5),
        Colony(300, 300, 3),
      ]),
    ]);
    expect(res.newPerFrame, [1, 1]);
    expect(
      res.tracks.firstWhere((t) => t.x > 5).growthMmPerH,
      closeTo(0.4 / 8, 1e-9),
    );
  });
}
