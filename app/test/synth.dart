import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// One synthetic plate in a test photo.
class SynthPlate {
  SynthPlate(
    this.cx,
    this.cy,
    this.radius, {
    this.colonies = 40,
    this.square = false,
    this.angle = 0,
    this.membrane = false,
    this.sizeMm = 90,
    this.colonyMm = 1.2,
    this.fixed = const [],
  });

  final double cx, cy, radius;
  final int colonies;
  final bool square, membrane;
  final double angle, sizeMm, colonyMm;

  /// Colony centres to use instead of random ones.
  final List<(double, double)> fixed;

  /// True colony centres (filled in by [synthPhoto]).
  final List<(double, double)> truth = [];

  double get mmPerPx => sizeMm / (2 * radius);

  bool inside(double x, double y, double f) {
    final dx = x - cx, dy = y - cy;
    if (!square) return dx * dx + dy * dy <= math.pow(radius * f, 2);
    final c = math.cos(angle), s = math.sin(angle);
    return (dx * c + dy * s).abs() <= radius * f &&
        (-dx * s + dy * c).abs() <= radius * f;
  }
}

/// Renders plates on a dark bench: agar with bright colonies, or a white
/// gridded membrane filter with dark colonies. Colonies are placed at random,
/// not touching, inside 85 % of the plate.
Uint8List synthPhoto(int w, int h, List<SynthPlate> plates, {int seed = 1}) {
  final rnd = math.Random(seed);
  final im = img.Image(width: w, height: h)..clear(img.ColorRgb8(25, 25, 28));
  for (final p in plates) {
    final reach = (p.radius * 1.5).ceil();
    for (
      var y = math.max(0, (p.cy - reach).floor());
      y < math.min(h, (p.cy + reach).ceil());
      y++
    ) {
      for (
        var x = math.max(0, (p.cx - reach).floor());
        x < math.min(w, (p.cx + reach).ceil());
        x++
      ) {
        if (!p.inside(x.toDouble(), y.toDouble(), 1)) continue;
        var v = p.membrane ? 225.0 : 120.0 + 20 * (x - p.cx) / p.radius;
        if (p.membrane) {
          // Grid lines every 3.1 mm, 0.15 mm wide, along the plate's axes.
          final c = math.cos(p.angle), s = math.sin(p.angle);
          final u = ((x - p.cx) * c + (y - p.cy) * s) * p.mmPerPx;
          final t = (-(x - p.cx) * s + (y - p.cy) * c) * p.mmPerPx;
          double off(double a) => ((a % 3.1) + 3.1) % 3.1;
          if (off(u) < 0.15 || off(t) < 0.15) v = 140;
        }
        im.setPixelRgb(x, y, v, v, v * 0.9);
      }
    }
    final rPx = p.colonyMm / 2 / p.mmPerPx;
    var tries = 0;
    var k = 0;
    while (p.truth.length < p.colonies + p.fixed.length && tries++ < 20000) {
      final fixed = k < p.fixed.length;
      final x = fixed
          ? p.fixed[k].$1
          : p.cx + (rnd.nextDouble() * 2 - 1) * p.radius;
      final y = fixed
          ? p.fixed[k++].$2
          : p.cy + (rnd.nextDouble() * 2 - 1) * p.radius;
      if (!fixed && !p.inside(x, y, 0.85)) continue;
      if (!fixed &&
          p.truth.any(
            (q) =>
                math.pow(q.$1 - x, 2) + math.pow(q.$2 - y, 2) <
                math.pow(3 * rPx, 2),
          )) {
        continue;
      }
      p.truth.add((x, y));
      for (var yy = (y - rPx - 2).floor(); yy <= (y + rPx + 2).ceil(); yy++) {
        for (var xx = (x - rPx - 2).floor(); xx <= (x + rPx + 2).ceil(); xx++) {
          final d = math.sqrt(math.pow(xx - x, 2) + math.pow(yy - y, 2));
          final a = (rPx + 0.5 - d).clamp(0.0, 1.0);
          if (a <= 0) continue;
          final px = im.getPixel(xx, yy);
          final target = p.membrane ? 60.0 : 225.0;
          final v = px.r * (1 - a) + target * a;
          im.setPixelRgb(xx, yy, v, v, v * (p.membrane ? 1.3 : 0.9));
        }
      }
    }
  }
  for (final px in im) {
    final n = rnd.nextDouble() * 6 - 3;
    px
      ..r = (px.r + n).clamp(0, 255)
      ..g = (px.g + n).clamp(0, 255)
      ..b = (px.b + n).clamp(0, 255);
  }
  return Uint8List.fromList(img.encodeJpg(im, quality: 92));
}
