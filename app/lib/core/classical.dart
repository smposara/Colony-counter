import 'dart:math' as math;
import 'dart:typed_data';

import 'gray_image.dart';

/// Tuning for the classical detector (mirrors ml/colonycounter/classical.py).
class DetectParams {
  const DetectParams({
    this.minDiameterMm = 0.15,
    this.kSigma = 4.0,
    this.minContrast = 6.0,
    this.peakSeparation = 0.5,
    this.spreaderFraction = 0.04,
  });

  final double minDiameterMm;

  /// Threshold in noise standard deviations; lower finds fainter colonies.
  final double kSigma;
  final double minContrast;

  /// Colonies closer than this fraction of a typical radius are treated as one.
  final double peakSeparation;

  /// A blob covering more than this fraction of the plate is a spreader.
  final double spreaderFraction;

  DetectParams copyWith({double? kSigma}) => DetectParams(
    minDiameterMm: minDiameterMm,
    kSigma: kSigma ?? this.kSigma,
    minContrast: minContrast,
    peakSeparation: peakSeparation,
    spreaderFraction: spreaderFraction,
  );
}

/// One counted mark. [n] > 1 when a merged cluster is estimated as several colonies.
class Colony {
  const Colony(
    this.x,
    this.y,
    this.radiusPx, {
    this.n = 1,
    this.score = 0,
    this.manual = false,
  });

  final double x;
  final double y;
  final double radiusPx;
  final int n;
  final double score;

  /// Added by the user during review.
  final bool manual;

  Colony scaled(double s) =>
      Colony(x * s, y * s, radiusPx * s, n: n, score: score, manual: manual);

  Colony withN(int n) =>
      Colony(x, y, radiusPx, n: n, score: score, manual: manual);

  Map<String, dynamic> toJson() => {
    'x': x,
    'y': y,
    'r': radiusPx,
    'n': n,
    if (score != 0) 'score': score,
    if (manual) 'manual': true,
  };

  factory Colony.fromJson(Map<String, dynamic> j) => Colony(
    (j['x'] as num).toDouble(),
    (j['y'] as num).toDouble(),
    (j['r'] as num).toDouble(),
    n: (j['n'] as num?)?.toInt() ?? 1,
    score: (j['score'] as num?)?.toDouble() ?? 0,
    manual: j['manual'] as bool? ?? false,
  );
}

class Detection {
  Detection(
    this.colonies,
    this.threshold,
    this.noiseSigma,
    this.coverage,
    this.spreaders,
  );

  final List<Colony> colonies;
  final double threshold;
  final double noiseSigma;
  final double coverage;
  final int spreaders;
}

double robustSigma(List<double> values) {
  if (values.isEmpty) return 1;
  final med = median(List.of(values));
  final dev = [for (final v in values) (v - med).abs()];
  final s = 1.4826 * median(dev);
  return s == 0 ? 1 : s;
}

/// Threshold the contrast map [fg], then split touching colonies at
/// distance-transform peaks.
Detection detect(
  GrayImage fg,
  Uint8List mask,
  double mmPerPx, [
  DetectParams params = const DetectParams(),
]) {
  final w = fg.width, h = fg.height;
  final sample = <double>[];
  for (var i = 0; i < mask.length; i += 3) {
    if (mask[i] == 1) sample.add(fg.data[i]);
  }
  final sigma = robustSigma(sample);
  final thr = math.max(params.kSigma * sigma, params.minContrast);

  var binary = Uint8List(w * h);
  var plateArea = 0;
  for (var i = 0; i < binary.length; i++) {
    if (mask[i] == 1) {
      plateArea++;
      if (fg.data[i] > thr) binary[i] = 1;
    }
  }
  binary = _dilate3(_erode3(binary, w, h), w, h);
  binary = _fillHoles(binary, w, h);

  final minR = params.minDiameterMm / mmPerPx / 2;
  final minArea = math.max(4.0, math.pi * minR * minR);
  final comps = _components(binary, w, h);
  final keep = [
    for (final c in comps.list)
      if (c.area >= minArea) c,
  ];
  if (keep.isEmpty) return Detection([], thr, sigma, 0, 0);

  final dist = _edt(binary, w, h);
  final radii = <double>[
    for (final c in keep)
      if (c.solidity > 0.9) math.sqrt(c.area / math.pi),
  ];
  if (radii.isEmpty) radii.addAll(keep.map((c) => math.sqrt(c.area / math.pi)));
  final typicalR = math.max(1.5, median(radii));
  final typicalArea = math.pi * typicalR * typicalR;
  final footprint = math.max(2, (params.peakSeparation * typicalR).round());
  final peaksByComp = _peaks(
    dist,
    comps.labels,
    w,
    h,
    footprint,
    math.max(1.0, 0.35 * typicalR),
  );

  final colonies = <Colony>[];
  var spreaders = 0;
  var covered = 0;
  for (final c in keep) {
    covered += c.area;
    final score = c.maxValue(fg) / sigma;
    if (c.area > params.spreaderFraction * plateArea) {
      spreaders++;
      continue;
    }
    final pts = peaksByComp[c.label] ?? const [];
    if (pts.length <= 1) {
      var n = 1;
      if (c.area > 2.5 * typicalArea && c.solidity < 0.85) {
        n = (c.area / typicalArea).round();
      }
      colonies.add(
        Colony(c.cx, c.cy, math.sqrt(c.area / math.pi), n: n, score: score),
      );
    } else {
      final r = math.sqrt(c.area / math.pi / pts.length);
      for (final p in pts) {
        colonies.add(Colony(p.$1, p.$2, r, score: score));
      }
    }
  }
  return Detection(
    colonies,
    thr,
    sigma,
    plateArea == 0 ? 0 : covered / plateArea,
    spreaders,
  );
}

// ---------------------------------------------------------------------------
// Binary image helpers

Uint8List _erode3(Uint8List b, int w, int h) {
  final out = Uint8List(w * h);
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final i = y * w + x;
      if (b[i] == 0) continue;
      if (b[i - w - 1] &
              b[i - w] &
              b[i - w + 1] &
              b[i - 1] &
              b[i + 1] &
              b[i + w - 1] &
              b[i + w] &
              b[i + w + 1] ==
          1) {
        out[i] = 1;
      }
    }
  }
  return out;
}

Uint8List _dilate3(Uint8List b, int w, int h) {
  final out = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (b[y * w + x] == 0) continue;
      for (var dy = -1; dy <= 1; dy++) {
        final yy = y + dy;
        if (yy < 0 || yy >= h) continue;
        for (var dx = -1; dx <= 1; dx++) {
          final xx = x + dx;
          if (xx >= 0 && xx < w) out[yy * w + xx] = 1;
        }
      }
    }
  }
  return out;
}

/// Sets enclosed background regions (not 4-connected to the border) to 1.
Uint8List _fillHoles(Uint8List b, int w, int h) {
  final outside = Uint8List(w * h);
  final stack = <int>[];
  void push(int i) {
    if (b[i] == 0 && outside[i] == 0) {
      outside[i] = 1;
      stack.add(i);
    }
  }

  for (var x = 0; x < w; x++) {
    push(x);
    push((h - 1) * w + x);
  }
  for (var y = 0; y < h; y++) {
    push(y * w);
    push(y * w + w - 1);
  }
  while (stack.isNotEmpty) {
    final i = stack.removeLast();
    final x = i % w, y = i ~/ w;
    if (x > 0) push(i - 1);
    if (x < w - 1) push(i + 1);
    if (y > 0) push(i - w);
    if (y < h - 1) push(i + w);
  }
  final out = Uint8List(w * h);
  for (var i = 0; i < out.length; i++) {
    out[i] = outside[i] == 1 ? 0 : 1;
  }
  return out;
}

class _Component {
  _Component(this.label);

  final int label;
  int area = 0;
  double sx = 0, sy = 0;
  final Map<int, (int, int)> rows = {}; // y -> (minX, maxX)
  final List<int> pixels = [];
  double solidity = 1;

  double get cx => sx / area;
  double get cy => sy / area;

  double maxValue(GrayImage img) {
    var m = -double.infinity;
    for (final i in pixels) {
      if (img.data[i] > m) m = img.data[i];
    }
    return m;
  }
}

class _Components {
  _Components(this.labels, this.list);

  final Int32List labels;
  final List<_Component> list;
}

_Components _components(Uint8List b, int w, int h) {
  final labels = Int32List(w * h);
  final list = <_Component>[];
  final stack = <int>[];
  for (var start = 0; start < b.length; start++) {
    if (b[start] == 0 || labels[start] != 0) continue;
    final c = _Component(list.length + 1);
    labels[start] = c.label;
    stack.add(start);
    while (stack.isNotEmpty) {
      final i = stack.removeLast();
      final x = i % w, y = i ~/ w;
      c.area++;
      c.sx += x;
      c.sy += y;
      c.pixels.add(i);
      final r = c.rows[y];
      c.rows[y] = r == null ? (x, x) : (math.min(r.$1, x), math.max(r.$2, x));
      for (var dy = -1; dy <= 1; dy++) {
        final yy = y + dy;
        if (yy < 0 || yy >= h) continue;
        for (var dx = -1; dx <= 1; dx++) {
          final xx = x + dx;
          if (xx < 0 || xx >= w) continue;
          final j = yy * w + xx;
          if (b[j] == 1 && labels[j] == 0) {
            labels[j] = c.label;
            stack.add(j);
          }
        }
      }
    }
    c.solidity = _solidity(c);
    list.add(c);
  }
  return _Components(labels, list);
}

/// Pixel count over the area of the convex hull of the pixel centres.
double _solidity(_Component c) {
  final pts = <(int, int)>[];
  c.rows.forEach((y, r) {
    pts.add((r.$1, y));
    if (r.$2 != r.$1) pts.add((r.$2, y));
  });
  if (pts.length < 3) return 1;
  pts.sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2);
  int cross((int, int) o, (int, int) a, (int, int) b) =>
      (a.$1 - o.$1) * (b.$2 - o.$2) - (a.$2 - o.$2) * (b.$1 - o.$1);
  final hull = <(int, int)>[];
  for (final p in pts) {
    while (hull.length >= 2 &&
        cross(hull[hull.length - 2], hull.last, p) <= 0) {
      hull.removeLast();
    }
    hull.add(p);
  }
  final lower = hull.length + 1;
  for (final p in pts.reversed.skip(1)) {
    while (hull.length >= lower &&
        cross(hull[hull.length - 2], hull.last, p) <= 0) {
      hull.removeLast();
    }
    hull.add(p);
  }
  hull.removeLast();
  var a2 = 0;
  for (var i = 0; i < hull.length; i++) {
    final p = hull[i], q = hull[(i + 1) % hull.length];
    a2 += p.$1 * q.$2 - q.$1 * p.$2;
  }
  final area = a2.abs() / 2;
  return area > 0 ? c.area / area : 1;
}

/// Exact Euclidean distance from each foreground pixel to the nearest background
/// pixel (Felzenszwalb & Huttenlocher). Pixels outside the image count as background.
Float32List _edt(Uint8List b, int w, int h) {
  const inf = 1e20;
  final f = Float64List(w * h);
  for (var i = 0; i < f.length; i++) {
    f[i] = b[i] == 1 ? inf : 0;
  }
  // Pad with one background pixel on each side so the border acts as background.
  final n = math.max(w, h) + 2;
  final line = Float64List(n), d = Float64List(n), z = Float64List(n + 1);
  final v = Int32List(n);

  void dt1(int len) {
    var k = 0;
    v[0] = 0;
    z[0] = -inf;
    z[1] = inf;
    for (var q = 1; q < len; q++) {
      var s =
          ((line[q] + q * q) - (line[v[k]] + v[k] * v[k])) / (2 * q - 2 * v[k]);
      while (s <= z[k]) {
        k--;
        s =
            ((line[q] + q * q) - (line[v[k]] + v[k] * v[k])) /
            (2 * q - 2 * v[k]);
      }
      k++;
      v[k] = q;
      z[k] = s;
      z[k + 1] = inf;
    }
    k = 0;
    for (var q = 0; q < len; q++) {
      while (z[k + 1] < q) {
        k++;
      }
      d[q] = (q - v[k]) * (q - v[k]) + line[v[k]];
    }
  }

  for (var x = 0; x < w; x++) {
    line[0] = 0;
    for (var y = 0; y < h; y++) {
      line[y + 1] = f[y * w + x];
    }
    line[h + 1] = 0;
    dt1(h + 2);
    for (var y = 0; y < h; y++) {
      f[y * w + x] = d[y + 1];
    }
  }
  for (var y = 0; y < h; y++) {
    line[0] = 0;
    for (var x = 0; x < w; x++) {
      line[x + 1] = f[y * w + x];
    }
    line[w + 1] = 0;
    dt1(w + 2);
    for (var x = 0; x < w; x++) {
      f[y * w + x] = d[x + 1];
    }
  }
  final out = Float32List(w * h);
  for (var i = 0; i < out.length; i++) {
    out[i] = math.sqrt(f[i]);
  }
  return out;
}

/// Local maxima of [dist] within a disk of radius [footprint], grouped into peak
/// regions; returns each region's centroid keyed by component label.
Map<int, List<(double, double)>> _peaks(
  Float32List dist,
  Int32List labels,
  int w,
  int h,
  int footprint,
  double minHeight,
) {
  final offsets = <(int, int)>[];
  for (var dy = -footprint; dy <= footprint; dy++) {
    for (var dx = -footprint; dx <= footprint; dx++) {
      if (dx * dx + dy * dy <= footprint * footprint) offsets.add((dx, dy));
    }
  }
  final isPeak = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      final v = dist[i];
      if (v < minHeight) continue;
      var ok = true;
      for (final (dx, dy) in offsets) {
        final xx = x + dx, yy = y + dy;
        // Outside the image counts as 0, which never beats a peak.
        if (xx < 0 || yy < 0 || xx >= w || yy >= h) continue;
        if (dist[yy * w + xx] > v) {
          ok = false;
          break;
        }
      }
      if (ok) isPeak[i] = 1;
    }
  }
  final comps = _components(isPeak, w, h);
  final out = <int, List<(double, double)>>{};
  for (final c in comps.list) {
    final px = c.cx, py = c.cy;
    final label = labels[py.round() * w + px.round()];
    if (label != 0) (out[label] ??= []).add((px, py));
  }
  return out;
}
