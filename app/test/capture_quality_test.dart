import 'dart:math' as math;
import 'dart:typed_data';

import 'package:colony_counter/core/capture_quality.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _checker(int w, int h, int cell, {int lo = 40, int hi = 200}) {
  final b = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      b[y * w + x] = ((x ~/ cell) + (y ~/ cell)).isEven ? lo : hi;
    }
  }
  return b;
}

Uint8List _boxBlur(Uint8List src, int w, int h, int r) {
  final out = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var s = 0, n = 0;
      for (var dy = -r; dy <= r; dy++) {
        for (var dx = -r; dx <= r; dx++) {
          final xx = (x + dx).clamp(0, w - 1), yy = (y + dy).clamp(0, h - 1);
          s += src[yy * w + xx];
          n++;
        }
      }
      out[y * w + x] = s ~/ n;
    }
  }
  return out;
}

void main() {
  test('tilt from gravity', () {
    expect(tiltDegrees(0, 0, 9.81), closeTo(0, 1e-9));
    expect(tiltDegrees(0, 9.81, 0), closeTo(90, 1e-9));
    final a = 5 * math.pi / 180;
    expect(
      tiltDegrees(9.81 * math.sin(a), 0, -9.81 * math.cos(a)),
      closeTo(5, 1e-6),
    );
  });

  test('sharp frames score higher than blurred ones', () {
    const w = 160, h = 120;
    final sharp = _checker(w, h, 4);
    final blurred = _boxBlur(sharp, w, h, 3);
    final qs = measureFrame(sharp, width: w, height: h, rowStride: w, step: 1);
    final qb = measureFrame(
      blurred,
      width: w,
      height: h,
      rowStride: w,
      step: 1,
    );
    expect(qs.sharpness, greaterThan(5 * qb.sharpness));
  });

  test('glare fraction counts clipped pixels in the guide circle only', () {
    const w = 100, h = 100;
    final b = Uint8List(w * h)..fillRange(0, w * h, 100);
    for (var y = 45; y < 55; y++) {
      for (var x = 45; x < 55; x++) {
        b[y * w + x] = 255;
      }
    }
    b[0] = 255; // outside the circle
    final q = measureFrame(b, width: w, height: h, rowStride: w, step: 1);
    expect(q.glareFraction, greaterThan(0.01));
    expect(q.glareFraction, lessThan(0.03));
  });

  test('BGRA frames use the green byte', () {
    const w = 40, h = 40;
    final bgra = Uint8List(w * h * 4);
    for (var i = 0; i < w * h; i++) {
      bgra[i * 4 + 1] = 255;
    }
    final q = measureFrame(
      bgra,
      width: w,
      height: h,
      rowStride: w * 4,
      pixelStride: 4,
      offset: 1,
      step: 1,
    );
    expect(q.glareFraction, 1.0);
  });

  test('sharpness tracker compares with recent best', () {
    final t = SharpnessTracker(window: 5);
    expect(t.add(100), isTrue);
    expect(t.add(30), isFalse);
    expect(t.add(90), isTrue);
  });
}
