import 'dart:math' as math;

import 'package:image/image.dart' as img;

import 'classical.dart';

/// A colour in CIE L*a*b* (D65): L 0–100 lightness, a green(−)…red(+),
/// b blue(−)…yellow(+).
class Lab {
  const Lab(this.l, this.a, this.b);

  final double l;
  final double a;
  final double b;

  double distanceTo(Lab o) => math.sqrt(
    math.pow(l - o.l, 2) + math.pow(a - o.a, 2) + math.pow(b - o.b, 2),
  );

  List<double> toJson() => [_r(l), _r(a), _r(b)];

  factory Lab.fromJson(List<dynamic> j) => Lab(
    (j[0] as num).toDouble(),
    (j[1] as num).toDouble(),
    (j[2] as num).toDouble(),
  );

  static double _r(double v) => (v * 10).round() / 10;
}

Lab rgbToLab(num r8, num g8, num b8) {
  double lin(num c) {
    final v = c / 255.0;
    return v <= 0.04045
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  }

  final r = lin(r8), g = lin(g8), b = lin(b8);
  final x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047;
  final y = 0.2126 * r + 0.7152 * g + 0.0722 * b;
  final z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883;
  double f(double t) =>
      t > 0.008856 ? math.pow(t, 1 / 3).toDouble() : 7.787 * t + 16 / 116;
  final fx = f(x), fy = f(y), fz = f(z);
  return Lab(116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz));
}

/// Mean colour of each colony's centre (inner 60 % of its radius), sampled from
/// [photo]. Colony coordinates must be in [photo]'s pixels.
List<Lab> colonyColours(img.Image photo, List<Colony> colonies) {
  final out = <Lab>[];
  for (final c in colonies) {
    final r = math.max(1.0, c.radiusPx * 0.6);
    final step = math.max(1, (r / 6).floor()); // ≤ ~150 samples per colony
    var sr = 0.0, sg = 0.0, sb = 0.0;
    var n = 0;
    for (var dy = -r; dy <= r; dy += step) {
      for (var dx = -r; dx <= r; dx += step) {
        if (dx * dx + dy * dy > r * r) continue;
        final x = (c.x + dx).round(), y = (c.y + dy).round();
        if (x < 0 || y < 0 || x >= photo.width || y >= photo.height) continue;
        final p = photo.getPixel(x, y);
        sr += p.r;
        sg += p.g;
        sb += p.b;
        n++;
      }
    }
    out.add(n == 0 ? const Lab(0, 0, 0) : rgbToLab(sr / n, sg / n, sb / n));
  }
  return out;
}

/// How colonies are split into colour classes.
enum ColourMode {
  none('Off', ['All']),

  /// X-gal blue/white screening: class 1 = blue.
  blueWhite('Blue / white', ['White', 'Blue']),

  /// Any two colony colours (e.g. chromogenic media): class 1 = less common.
  twoColours('Two colours', ['Colour A', 'Colour B']);

  const ColourMode(this.label, this.classNames);

  final String label;
  final List<String> classNames;
}

/// Minimum colour difference (ΔE) between two groups for them to count as
/// genuinely different colours rather than noise.
const double kMinColourGap = 6;

/// Assigns each colour a class (0 or 1) for [mode].
List<int> classifyColours(List<Lab> colours, ColourMode mode) {
  if (colours.isEmpty || mode == ColourMode.none) {
    return List.filled(colours.length, 0);
  }
  if (mode == ColourMode.blueWhite) {
    final bs = [for (final c in colours) c.b];
    final (lo, hi, split) = _twoMeans1d(bs);
    if (hi - lo < kMinColourGap) {
      // One population: call it blue only if clearly blue.
      final all = (bs.reduce((a, b) => a + b) / bs.length) < -kMinColourGap
          ? 1
          : 0;
      return List.filled(colours.length, all);
    }
    return [for (final b in bs) b < split ? 1 : 0];
  }
  // Two colours: 2-means on chroma (a*, b*); the minority class is 1.
  final labels = _twoMeans2d(colours);
  if (labels == null) return List.filled(colours.length, 0);
  final ones = labels.where((l) => l == 1).length;
  return ones * 2 > labels.length ? [for (final l in labels) 1 - l] : labels;
}

(double, double, double) _twoMeans1d(List<double> v) {
  final sorted = List.of(v)..sort();
  var lo = sorted.first, hi = sorted.last;
  for (var it = 0; it < 20; it++) {
    final split = (lo + hi) / 2;
    final a = v.where((x) => x < split).toList();
    final b = v.where((x) => x >= split).toList();
    if (a.isEmpty || b.isEmpty) break;
    lo = a.reduce((p, q) => p + q) / a.length;
    hi = b.reduce((p, q) => p + q) / b.length;
  }
  return (lo, hi, (lo + hi) / 2);
}

List<int>? _twoMeans2d(List<Lab> cs) {
  // Start from the two most different colours.
  var i0 = 0, i1 = 0;
  var best = -1.0;
  final step = math.max(1, cs.length ~/ 60);
  for (var i = 0; i < cs.length; i += step) {
    for (var j = i + 1; j < cs.length; j += step) {
      final d = _chroma(cs[i], cs[j]);
      if (d > best) {
        best = d;
        i0 = i;
        i1 = j;
      }
    }
  }
  var c0 = (cs[i0].a, cs[i0].b), c1 = (cs[i1].a, cs[i1].b);
  var labels = List.filled(cs.length, 0);
  for (var it = 0; it < 20; it++) {
    labels = [for (final c in cs) _d2(c, c0) <= _d2(c, c1) ? 0 : 1];
    (double, double) mean(int k) {
      var sa = 0.0, sb = 0.0;
      var n = 0;
      for (var i = 0; i < cs.length; i++) {
        if (labels[i] == k) {
          sa += cs[i].a;
          sb += cs[i].b;
          n++;
        }
      }
      return n == 0 ? (k == 0 ? c0 : c1) : (sa / n, sb / n);
    }

    c0 = mean(0);
    c1 = mean(1);
  }
  final gap = math.sqrt(
    math.pow(c0.$1 - c1.$1, 2) + math.pow(c0.$2 - c1.$2, 2),
  );
  return gap < kMinColourGap ? null : labels;
}

double _chroma(Lab x, Lab y) =>
    math.sqrt(math.pow(x.a - y.a, 2) + math.pow(x.b - y.b, 2));
double _d2(Lab c, (double, double) m) =>
    math.pow(c.a - m.$1, 2) + math.pow(c.b - m.$2, 2).toDouble();
