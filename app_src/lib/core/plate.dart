import 'dart:math' as math;
import 'dart:typed_data';

import 'gray_image.dart';

const double kDefaultPlateDiameterMm = 90.0;

/// A circular plate in image pixel coordinates.
class Plate {
  const Plate(this.cx, this.cy, this.radius, {this.diameterMm = kDefaultPlateDiameterMm});

  final double cx;
  final double cy;
  final double radius;
  final double diameterMm;

  double get mmPerPx => diameterMm / (2 * radius);

  Plate scaled(double s) => Plate(cx * s, cy * s, radius * s, diameterMm: diameterMm);

  Plate copyWith({double? cx, double? cy, double? radius}) =>
      Plate(cx ?? this.cx, cy ?? this.cy, radius ?? this.radius, diameterMm: diameterMm);

  /// 1 inside the counted area (radius x [rimFraction]), 0 outside.
  Uint8List mask(int width, int height, {double rimFraction = 0.95}) {
    final m = Uint8List(width * height);
    final r = radius * rimFraction;
    final r2 = r * r;
    final y0 = math.max(0, (cy - r).floor()), y1 = math.min(height - 1, (cy + r).ceil());
    for (var y = y0; y <= y1; y++) {
      final dy = y - cy;
      final rem = r2 - dy * dy;
      if (rem < 0) continue;
      final half = math.sqrt(rem);
      final x0 = math.max(0, (cx - half).ceil()), x1 = math.min(width - 1, (cx + half).floor());
      for (var x = x0; x <= x1; x++) {
        m[y * width + x] = 1;
      }
    }
    return m;
  }

  Map<String, dynamic> toJson() =>
      {'cx': cx, 'cy': cy, 'radius': radius, 'diameter_mm': diameterMm};

  factory Plate.fromJson(Map<String, dynamic> j) => Plate(
        (j['cx'] as num).toDouble(),
        (j['cy'] as num).toDouble(),
        (j['radius'] as num).toDouble(),
        diameterMm: (j['diameter_mm'] as num?)?.toDouble() ?? kDefaultPlateDiameterMm,
      );
}

/// Finds the dish as the circle with the strongest radial edge.
///
/// A coarse-to-fine search over centre and radius on a small copy of the image,
/// scoring each circle by the mean |radial gradient| along its edge. Works for both
/// the lightbox (black surround) and freehand photos. [minFill] and [maxFill] bound
/// the dish diameter as a fraction of the image's shorter side.
Plate findPlate(
  GrayImage image, {
  double diameterMm = kDefaultPlateDiameterMm,
  double minFill = 0.4,
  double maxFill = 1.1,
  int workSize = 320,
}) {
  final scale = workSize / math.max(image.width, image.height);
  final small = image
      .resize((image.width * scale).round(), (image.height * scale).round())
      .gaussianBlur(1.2);
  final w = small.width, h = small.height;
  final gx = Float32List(w * h), gy = Float32List(w * h);
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final i = y * w + x;
      gx[i] = (small.data[i + 1] - small.data[i - 1]) / 2;
      gy[i] = (small.data[i + w] - small.data[i - w]) / 2;
    }
  }
  final short = math.min(w, h).toDouble();

  double score(double cx, double cy, double r) {
    const n = 120;
    var s = 0.0;
    var cnt = 0;
    for (var k = 0; k < n; k++) {
      final a = 2 * math.pi * k / n;
      final c = math.cos(a), sn = math.sin(a);
      final x = (cx + r * c).round(), y = (cy + r * sn).round();
      if (x < 1 || y < 1 || x >= w - 1 || y >= h - 1) continue;
      final i = y * w + x;
      s += (gx[i] * c + gy[i] * sn).abs();
      cnt++;
    }
    // Circles that leave the image are penalised by their missing samples.
    return cnt == 0 ? 0 : s / n;
  }

  var best = (score: -1.0, cx: w / 2, cy: h / 2, r: short * 0.4);
  void search(double cx0, double cy0, double cRange, double cStep, double r0, double r1, double rStep) {
    for (var cy = cy0 - cRange; cy <= cy0 + cRange; cy += cStep) {
      for (var cx = cx0 - cRange; cx <= cx0 + cRange; cx += cStep) {
        for (var r = r0; r <= r1; r += rStep) {
          final s = score(cx, cy, r);
          if (s > best.score) best = (score: s, cx: cx, cy: cy, r: r);
        }
      }
    }
  }

  final rMin = short * minFill / 2, rMax = short * maxFill / 2;
  search(w / 2, h / 2, short * 0.2, short * 0.02, rMin, rMax, short * 0.01);
  final b1 = best;
  search(b1.cx, b1.cy, short * 0.02, 1, b1.r - short * 0.01, b1.r + short * 0.01, 0.5);
  final b2 = best;
  search(b2.cx, b2.cy, 1, 0.25, b2.r - 1, b2.r + 1, 0.25);

  if (best.score <= 0) {
    throw StateError('No plate found in image');
  }
  return Plate(best.cx / scale, best.cy / scale, best.r / scale, diameterMm: diameterMm);
}
