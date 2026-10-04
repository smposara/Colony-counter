import 'dart:math' as math;

import 'package:colony_counter/core/pipeline.dart';
import 'package:colony_counter/core/plate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'synth.dart';

void main() {
  test('60 mm dish: scale from the format', () {
    final p = SynthPlate(600, 500, 400, sizeMm: 60, colonies: 50);
    final res = countPhoto(
      synthPhoto(1200, 1000, [p]),
      const CountOptions(format: PlateFormat.dish60),
    );
    expect(res.plate.mmPerPx, closeTo(60 / 800, 0.003));
    expect(res.count, inInclusiveRange(47, 53));
  });

  test('square plate, turned 8°', () {
    final p = SynthPlate(
      620,
      500,
      380,
      square: true,
      angle: 8 * math.pi / 180,
      sizeMm: 100,
      colonies: 60,
    );
    final res = countPhoto(
      synthPhoto(1240, 1000, [p], seed: 2),
      const CountOptions(format: PlateFormat.square100),
    );
    expect(res.plate.isSquare, isTrue);
    expect(res.plate.cx, closeTo(620, 8));
    expect(res.plate.cy, closeTo(500, 8));
    expect(res.plate.radius, closeTo(380, 10));
    expect(res.plate.angle * 180 / math.pi, closeTo(8, 1.5));
    expect(res.count, inInclusiveRange(58, 62));
  });

  test('gridded membrane filter: grid lines are not counted', () {
    final p = SynthPlate(
      600,
      500,
      420,
      membrane: true,
      sizeMm: 47,
      colonyMm: 1.0,
      colonies: 45,
    );
    final photo = synthPhoto(1200, 1000, [p], seed: 3);
    final res = countPhoto(
      photo,
      const CountOptions(format: PlateFormat.membrane47),
    );
    expect(res.plate.mmPerPx, closeTo(47 / 840, 0.003));
    expect(res.count, inInclusiveRange(41, 49));
  });

  test('several plates in one photo, in reading order', () {
    final plates = [
      SynthPlate(300, 280, 220, colonies: 20),
      SynthPlate(800, 290, 225, colonies: 30),
      SynthPlate(1300, 270, 220, colonies: 10),
      SynthPlate(550, 760, 222, colonies: 40),
    ];
    final bytes = synthPhoto(1600, 1050, plates, seed: 4);
    final gray = grayFromImage(img.decodeImage(bytes)!);
    final found = findPlates(gray);
    expect(found.length, 4);
    for (var i = 0; i < 4; i++) {
      expect(found[i].cx, closeTo(plates[i].cx, 10));
      expect(found[i].cy, closeTo(plates[i].cy, 10));
      expect(found[i].radius, closeTo(plates[i].radius, 10));
    }
  });
}
