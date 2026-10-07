import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'classical.dart';
import 'gray_image.dart';
import 'normalize.dart';
import 'pipeline.dart' show kWorkShortSide;
import 'plate.dart';
import 'zones.dart'
    show RingTaps, fitCircle, kRingSectors, sampleBilinear, sobel3;

// Counting Petrifilm-style dry-film plates (Neogen® Petrifilm® and similar);
// a port of ml/colonycounter/petrifilm.py, checked against it by
// test/petrifilm_core_test.dart.
//
//     photo → printed 1 cm grid (angle, pitch → mm/px, line positions)
//           → grid lines replaced by the colour from across the line
//           → round growth area (the tinted gel) → background per Lab channel
//           → colonies where the gel is darker / changes colour
//           → per colony: colour (blue / red), gas bubble within one colony
//             diameter, yellow zone, yeast vs mold by size
//           → results per the interpretation guide; above the counting range
//             an estimate from complete 1 cm squares × growth area
//
// Plate-type values with `confirmed: false` must be checked against the
// current Neogen interpretation guide before release (see docs/PETRIFILM.md).
// Petrifilm and Neogen are trademarks of Neogen Corporation.

class FilmType {
  const FilmType(
    this.key,
    this.label,
    this.results,
    this.countMin,
    this.countMax,
    this.areaCm2,
    this.foam,
    this.confirmed,
    this.source,
  );

  final String key;
  final String label;

  /// What is reported, in order.
  final List<String> results;
  final int countMin;
  final int countMax;

  /// Growth area used for square-based estimates.
  final double areaCm2;

  /// Growth area bounded by a foam ring.
  final bool foam;

  /// Range and area checked against the current guide.
  final bool confirmed;
  final String source;
}

const Map<String, FilmType> kFilmTypes = {
  'ac': FilmType(
    'ac',
    'Aerobic Count (AC)',
    ['aerobic'],
    25,
    250,
    20,
    false,
    true,
    'AC interpretation guide: 25-250 preferred, ~20 cm², square × 20',
  ),
  'ec': FilmType(
    'ec',
    'E. coli/Coliform (EC)',
    ['ecoli', 'coliform'],
    15,
    150,
    20,
    true,
    false,
    'EC interpretation guide: counting limit 150 (lower limit and area to confirm)',
  ),
  'cc': FilmType(
    'cc',
    'Coliform Count (CC)',
    ['coliform'],
    15,
    150,
    20,
    true,
    false,
    'CC interpretation guide (to confirm)',
  ),
  'eb': FilmType(
    'eb',
    'Enterobacteriaceae (EB)',
    ['enterobacteriaceae'],
    15,
    100,
    20,
    true,
    false,
    'EB interpretation guide (to confirm)',
  ),
  'ym': FilmType(
    'ym',
    'Yeast & Mold (YM)',
    ['yeast', 'mold'],
    15,
    150,
    20,
    true,
    false,
    'YM / Rapid YM interpretation guides (to confirm)',
  ),
};

const double kNominalAreaDiameterMm = 50.5; // 20 cm²
const double kGridPitchMm = 10.0;

/// The printed grid. Line positions are `ox + k * pitchPx` (and `oy + ...`) in
/// the frame turned by [angleDeg] about ([cx], [cy]).
class FilmGrid {
  const FilmGrid(
    this.pitchPx,
    this.angleDeg,
    this.ox,
    this.oy,
    this.cx,
    this.cy, [
    this.lineHalfPx = 2.0,
  ]);

  final double pitchPx;

  /// Rotate the image by this to make the grid axis-aligned.
  final double angleDeg;
  final double ox;
  final double oy;
  final double cx;
  final double cy;

  /// Erased on each side of a line's centre.
  final double lineHalfPx;

  double get mmPerPx => kGridPitchMm / pitchPx;

  (double, double) toGrid(double x, double y) {
    final r = _rot(angleDeg, cx, cy);
    return (r.a * x + r.b * y + r.tx, -r.b * x + r.a * y + r.ty);
  }

  (double, double) toImage(double gx, double gy) {
    final r = _rot(angleDeg, cx, cy);
    final u = gx - r.tx, v = gy - r.ty;
    return (r.a * u - r.b * v, r.b * u + r.a * v);
  }

  FilmGrid scaled(double s) => FilmGrid(
    pitchPx * s,
    angleDeg,
    ox * s,
    oy * s,
    cx * s,
    cy * s,
    lineHalfPx * s,
  );

  Map<String, dynamic> toJson() => {'pitch_px': pitchPx, 'angle_deg': angleDeg};
}

class FilmColony {
  const FilmColony(
    this.x,
    this.y,
    this.radiusPx,
    this.kind, {
    this.n = 1,
    this.gas = false,
    this.yellow = false,
  });

  final double x;
  final double y;
  final double radiusPx;

  /// "colony" (AC), "blue", "red", "yeast" or "mold".
  final String kind;
  final int n;
  final bool gas;
  final bool yellow;

  FilmColony scaled(double s) => FilmColony(
    x * s,
    y * s,
    radiusPx * s,
    kind,
    n: n,
    gas: gas,
    yellow: yellow,
  );

  Map<String, dynamic> toJson() => {
    'x': x,
    'y': y,
    'r': radiusPx,
    'kind': kind,
    'n': n,
    if (gas) 'gas': true,
    if (yellow) 'yellow': true,
  };
}

typedef Bubble = (double x, double y, double radiusPx);

class FilmResult {
  const FilmResult({
    required this.type,
    required this.plate,
    required this.grid,
    required this.colonies,
    required this.bubbles,
    required this.counts,
    required this.estimates,
    required this.squaresUsed,
    required this.flags,
  });

  final String type;

  /// The growth area.
  final Plate plate;
  final FilmGrid grid;
  final List<FilmColony> colonies;
  final List<Bubble> bubbles;

  /// Counted per result, in the type's order.
  final Map<String, int> counts;

  /// From complete squares, when above the counting range.
  final Map<String, double>? estimates;
  final int squaresUsed;
  final List<String> flags;

  /// Per-plate result: the estimate when there is one, else the count.
  Map<String, double> get values =>
      estimates ?? {for (final e in counts.entries) e.key: e.value.toDouble()};

  FilmResult scaled(double s) => FilmResult(
    type: type,
    plate: plate.scaled(s),
    grid: grid.scaled(s),
    colonies: [for (final c in colonies) c.scaled(s)],
    bubbles: [for (final (x, y, r) in bubbles) (x * s, y * s, r * s)],
    counts: counts,
    estimates: estimates,
    squaresUsed: squaresUsed,
    flags: flags,
  );

  Map<String, dynamic> toJson() => {
    'type': type,
    'counts': counts,
    'estimates': estimates,
    'squares_used': squaresUsed,
    'flags': flags,
    'mm_per_px': plate.mmPerPx,
    'plate': plate.toJson(),
    'grid': grid.toJson(),
    'colonies': [for (final c in colonies) c.toJson()],
    'bubbles': [
      for (final (x, y, r) in bubbles) [x, y, r],
    ],
  };
}

// ---------------------------------------------------------------------------
// Colour planes

/// Red, green and blue planes (0–255) of a decoded image.
List<GrayImage> _rgbPlanes(img.Image image) {
  final w = image.width, h = image.height;
  final r = GrayImage(w, h), g = GrayImage(w, h), b = GrayImage(w, h);
  var i = 0;
  for (final p in image) {
    r.data[i] = p.r.toDouble();
    g.data[i] = p.g.toDouble();
    b.data[i] = p.b.toDouble();
    i++;
  }
  return [r, g, b];
}

/// 8-bit gray as OpenCV computes it (fixed-point, rounded).
GrayImage _gray(List<GrayImage> rgb) {
  final w = rgb[0].width, h = rgb[0].height;
  final out = GrayImage(w, h);
  final r = rgb[0].data, g = rgb[1].data, b = rgb[2].data;
  for (var i = 0; i < out.data.length; i++) {
    out.data[i] =
        ((r[i].toInt() * 4899 +
                    g[i].toInt() * 9617 +
                    b[i].toInt() * 1868 +
                    8192) >>
                14)
            .toDouble();
  }
  return out;
}

final Float64List _linLut = Float64List.fromList([
  for (var c = 0; c < 256; c++)
    c / 255 <= 0.04045
        ? c / 255 / 12.92
        : math.pow((c / 255 + 0.055) / 1.055, 2.4).toDouble(),
]);

/// CIE Lab (D65, as rgbToLab) scaled like OpenCV's 8-bit images:
/// L·255/100, a + 128, b + 128, rounded. Written into [lab] within the box.
void _labInto(
  List<GrayImage> rgb,
  List<GrayImage> lab,
  int x0,
  int y0,
  int x1,
  int y1,
) {
  final w = rgb[0].width;
  final rd = rgb[0].data, gd = rgb[1].data, bd = rgb[2].data;
  double f(double t) =>
      t > 0.008856 ? math.pow(t, 1 / 3).toDouble() : 7.787 * t + 16 / 116;
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      final i = y * w + x;
      final r = _linLut[rd[i].toInt()],
          g = _linLut[gd[i].toInt()],
          b = _linLut[bd[i].toInt()];
      final fx = f((0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047);
      final fy = f(0.2126 * r + 0.7152 * g + 0.0722 * b);
      final fz = f((0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883);
      lab[0].data[i] = ((116 * fy - 16) * 255 / 100)
          .round()
          .clamp(0, 255)
          .toDouble();
      lab[1].data[i] = (500 * (fx - fy) + 128).round().clamp(0, 255).toDouble();
      lab[2].data[i] = (200 * (fy - fz) + 128).round().clamp(0, 255).toDouble();
    }
  }
}

List<GrayImage> _lab(List<GrayImage> rgb) {
  final w = rgb[0].width, h = rgb[0].height;
  final lab = [GrayImage(w, h), GrayImage(w, h), GrayImage(w, h)];
  _labInto(rgb, lab, 0, 0, w, h);
  return lab;
}

// ---------------------------------------------------------------------------
// Grid

({double a, double b, double tx, double ty}) _rot(
  double angleDeg,
  double cx,
  double cy,
) {
  final t = angleDeg * math.pi / 180;
  final a = math.cos(t), b = math.sin(t);
  return (a: a, b: b, tx: (1 - a) * cx - b * cy, ty: b * cx + (1 - a) * cy);
}

/// Separable k×k minimum (or maximum) with the border replicated.
Float32List _minMax(Float32List src, int w, int h, int k, bool max) {
  final r = k ~/ 2;
  final tmp = Float32List(w * h), out = Float32List(w * h);
  for (var y = 0; y < h; y++) {
    final row = y * w;
    for (var x = 0; x < w; x++) {
      var v = src[row + x];
      for (var i = -r; i <= r; i++) {
        final xx = x + i < 0 ? 0 : (x + i >= w ? w - 1 : x + i);
        final s = src[row + xx];
        if (max ? s > v : s < v) v = s;
      }
      tmp[row + x] = v;
    }
  }
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var v = tmp[y * w + x];
      for (var i = -r; i <= r; i++) {
        final yy = y + i < 0 ? 0 : (y + i >= h ? h - 1 : y + i);
        final s = tmp[yy * w + x];
        if (max ? s > v : s < v) v = s;
      }
      out[y * w + x] = v;
    }
  }
  return out;
}

/// Thin dark lines: black top-hat with a k×k square, minus its opening with a
/// [linePx] square, which keeps only the blobs (colonies) wider than a line.
Float32List _lineMap(GrayImage g, int k, [int linePx = 3]) {
  final w = g.width, h = g.height;
  final closed = _minMax(_minMax(g.data, w, h, k, true), w, h, k, false);
  final bth = Float32List(w * h);
  for (var i = 0; i < bth.length; i++) {
    bth[i] = closed[i] - g.data[i];
  }
  final blobs = _minMax(_minMax(bth, w, h, linePx, false), w, h, linePx, true);
  for (var i = 0; i < bth.length; i++) {
    bth[i] -= blobs[i];
  }
  return bth;
}

/// Sums (or means) of [v] along the columns and rows of the image turned by
/// [angle], without resampling it: each pixel is added to the two nearest bins
/// of its turned x (and y) coordinate.
(Float64List, Float64List) projections(
  Float32List v,
  int w,
  int h,
  double angle,
  double cx,
  double cy, {
  bool mean = false,
}) {
  final r = _rot(angle, cx, cy);
  final sx = Float64List(w), sy = Float64List(h);
  final nx = mean ? Float64List(w) : null, ny = mean ? Float64List(h) : null;
  for (var y = 0; y < h; y++) {
    final ux0 = r.b * y + r.tx, uy0 = r.a * y + r.ty;
    for (var x = 0; x < w; x++) {
      final val = v[y * w + x];
      final u = r.a * x + ux0;
      final i = u.floor();
      if (i >= 0 && i < w - 1) {
        final f = u - i;
        sx[i] += val * (1 - f);
        sx[i + 1] += val * f;
        if (nx != null) {
          nx[i] += 1 - f;
          nx[i + 1] += f;
        }
      }
      final t = -r.b * x + uy0;
      final j = t.floor();
      if (j >= 0 && j < h - 1) {
        final f = t - j;
        sy[j] += val * (1 - f);
        sy[j + 1] += val * f;
        if (ny != null) {
          ny[j] += 1 - f;
          ny[j + 1] += f;
        }
      }
    }
  }
  if (mean) {
    for (var i = 0; i < w; i++) {
      sx[i] = nx![i] > 0.5 ? sx[i] / nx[i] : 0;
    }
    for (var j = 0; j < h; j++) {
      sy[j] = ny![j] > 0.5 ? sy[j] / ny[j] : 0;
    }
  }
  return (sx, sy);
}

double _variance(Float64List v) {
  var m = 0.0;
  for (final x in v) {
    m += x;
  }
  m /= v.length;
  var s = 0.0;
  for (final x in v) {
    s += (x - m) * (x - m);
  }
  return s / v.length;
}

/// Angle, pitch and line positions of the printed grid.
///
/// On a line map (thin dark detail): the angle is the rotation whose column
/// and row sums are most peaked (largest variance), coarse to fine (1°, 0.1°,
/// 0.02°); the pitch comes from the autocorrelation of the full-resolution
/// sums, then the lines' offset and width.
FilmGrid findGrid(GrayImage gray) {
  final w = gray.width, h = gray.height;
  var angle = 0.0;
  var s = 1.0;
  late GrayImage small;
  late Float32List linesS;
  for (final (size, span, step) in const [
    (350.0, 45.0, 1.0),
    (700.0, 1.5, 0.1),
    (700.0, 0.12, 0.02),
  ]) {
    s = math.min(1.0, size / math.max(h, w));
    small = s < 1
        ? gray.resize(
            math.max(1, (w * s).round()),
            math.max(1, (h * s).round()),
          )
        : gray;
    linesS = _lineMap(small, 5);
    var m = 0.0;
    for (final x in linesS) {
      m += x;
    }
    m /= linesS.length;
    for (var i = 0; i < linesS.length; i++) {
      linesS[i] -= m;
    }
    final csx = small.width / 2, csy = small.height / 2;
    final lo = span < 45 ? angle - span : -45.0;
    final hi = span < 45 ? angle + span + 1e-9 : 45.0;
    final n = ((hi - lo) / step).ceil();
    var best = lo, bestScore = -double.infinity;
    for (var i = 0; i < n; i++) {
      final a = lo + i * step;
      final (px, py) = projections(
        linesS,
        small.width,
        small.height,
        a,
        csx,
        csy,
      );
      final sc = _variance(px) + _variance(py);
      if (sc > bestScore) {
        best = a;
        bestScore = sc;
      }
    }
    angle = best;
  }
  final (spx, spy) = projections(
    linesS,
    small.width,
    small.height,
    angle,
    small.width / 2,
    small.height / 2,
    mean: true,
  );
  final hiP = math.min(small.width, small.height) / 3;
  final coarse =
      (_firstPeriod(spx, 12, hiP) + _firstPeriod(spy, 12, hiP)) / 2 / s;

  final cx = w / 2, cy = h / 2;
  // ~0.6 mm and ~0.35 mm: both wider than a line.
  final k = math.max(5, (0.6 * coarse / kGridPitchMm).round() | 1);
  final lw = math.max(3, (0.35 * coarse / kGridPitchMm).round() | 1);
  final (px, py) = projections(_lineMap(gray, k, lw), w, h, angle, cx, cy);
  final pitch = (_refinePeriod(px, coarse) + _refinePeriod(py, coarse)) / 2;
  final ox = _phase(px, pitch), oy = _phase(py, pitch);
  final half =
      (_lineHalfWidth(px, pitch, ox) + _lineHalfWidth(py, pitch, oy)) / 2;
  return FilmGrid(pitch, angle, ox, oy, cx, cy, half);
}

Float64List _centred(Float64List p) {
  var m = 0.0;
  for (final x in p) {
    m += x;
  }
  m /= p.length;
  return Float64List.fromList([for (final x in p) x - m]);
}

/// Autocorrelation of [p] at lags [from]..[to] (inclusive), indexed by lag.
Float64List _autocorr(Float64List p, int from, int to) {
  final n = p.length;
  final ac = Float64List(to + 1);
  for (var lag = math.max(0, from); lag <= to && lag < n; lag++) {
    var s = 0.0;
    for (var i = 0; i + lag < n; i++) {
      s += p[i] * p[i + lag];
    }
    ac[lag] = s;
  }
  return ac;
}

/// Shortest lag with a strong autocorrelation peak (not a multiple of it).
double _firstPeriod(Float64List profile, double lo, double hi) {
  final n = profile.length;
  final loI = lo.toInt(), hiI = math.min(hi.toInt(), n - 2);
  if (hiI <= loI) return lo;
  final ac = _autocorr(_centred(profile), 0, hiI);
  var top = -double.infinity;
  var arg = loI;
  for (var i = loI; i < hiI; i++) {
    if (ac[i] > top) {
      top = ac[i];
      arg = i;
    }
  }
  for (var i = loI + 1; i < hiI; i++) {
    if (ac[i] >= 0.6 * top && ac[i] >= ac[i - 1] && ac[i] >= ac[i + 1]) {
      return i.toDouble();
    }
  }
  return arg.toDouble();
}

/// Sub-pixel period from the autocorrelation peak near [guess].
double _refinePeriod(Float64List profile, double guess) {
  final n = profile.length;
  final lo = (guess * 0.85).toInt();
  final hi = math.min((guess * 1.15).toInt() + 2, n);
  final ac = _autocorr(_centred(profile), lo - 1, math.min(hi, n - 1));
  var i = lo;
  for (var j = lo; j < hi; j++) {
    if (ac[j] > ac[i]) i = j;
  }
  if (i > 0 && i < n - 1 && i + 1 < ac.length) {
    final a = ac[i - 1], b = ac[i], c = ac[i + 1];
    final den = a - 2 * b + c;
    if (den < 0) return i + 0.5 * (a - c) / den;
  }
  return i.toDouble();
}

/// Linear interpolation of [p] at [x], clamped to its ends (as np.interp).
double _interp(Float64List p, double x) {
  if (x <= 0) return p[0];
  final n = p.length;
  if (x >= n - 1) return p[n - 1];
  final i = x.floor();
  final t = x - i;
  return p[i] * (1 - t) + p[i + 1] * t;
}

/// Mean of [p] at start, start + step, … below the last sample.
double _combMean(Float64List p, double start, double step) {
  final end = p.length - 1;
  final n = ((end - start) / step).ceil();
  if (n <= 0) return double.nan;
  var s = 0.0;
  for (var k = 0; k < n; k++) {
    s += _interp(p, start + k * step);
  }
  return s / n;
}

/// Offset of the lines: argmax over φ of the profile summed at φ + k·pitch.
double _phase(Float64List profile, double pitch) {
  var best = 0.0, bestV = -double.infinity;
  final n = (pitch / 0.25).ceil();
  for (var i = 0; i < n; i++) {
    final phi = i * 0.25;
    final v = _combMean(profile, phi, pitch);
    if (v > bestV) {
      best = phi;
      bestV = v;
    }
  }
  return best;
}

/// Half the width of an average line (where the folded profile falls to a
/// fifth of its height above the baseline), plus a pixel.
double _lineHalfWidth(Float64List profile, double pitch, double offset) {
  final n = ((pitch / 2 + 1e-9) / 0.25).ceil();
  final d = [for (var i = 0; i < n; i++) -pitch / 4 + i * 0.25];
  final fold = [for (final t in d) _combMean(profile, offset + t, pitch)];
  final base = median([
    for (var i = 0; i < n; i++)
      if (d[i].abs() > pitch / 8) fold[i],
  ]);
  var c = 0;
  for (var i = 1; i < n; i++) {
    if (d[i].abs() < d[c].abs()) c = i;
  }
  final top = fold[c] - base;
  if (top <= 0) return 2.0;
  var above = 0.0;
  for (var i = 0; i < n; i++) {
    if (fold[i] - base >= 0.2 * top) above = math.max(above, d[i].abs());
  }
  return (above + 1.0).clamp(1.5, pitch / 6).toDouble();
}

/// Erases the printed lines inside [region] (with a margin): each line pixel
/// takes the colour just across the line, interpolated by position; where two
/// lines cross, the four diagonal neighbours outside both lines. Returns the
/// new planes and the box that may have changed.
(List<GrayImage>, (int, int, int, int)) fillGridLines(
  List<GrayImage> planes,
  FilmGrid grid,
  double half,
  Plate region,
) {
  final w = planes[0].width, h = planes[0].height;
  final out = [for (final p in planes) p.copy()];
  final m = region.radius * 1.1 + half + 2;
  final x0 = math.max(0, (region.cx - m).toInt()),
      x1 = math.min(w, (region.cx + m).toInt() + 1);
  final y0 = math.max(0, (region.cy - m).toInt()),
      y1 = math.min(h, (region.cy + m).toInt() + 1);
  final p = grid.pitchPx, e = half + 1.0;
  final vals = Float64List(planes.length);

  void add(double gx, double gy, double wgt) {
    final (ix, iy) = grid.toImage(gx, gy);
    for (var c = 0; c < planes.length; c++) {
      vals[c] += wgt * sampleBilinear(planes[c], ix, iy);
    }
  }

  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      final (gx, gy) = grid.toGrid(x.toDouble(), y.toDouble());
      // Signed offset from the nearest line.
      final dx = (gx - grid.ox + p / 2) % p - p / 2;
      final dy = (gy - grid.oy + p / 2) % p - p / 2;
      final inx = dx.abs() < half, iny = dy.abs() < half;
      if (!inx && !iny) continue;
      vals.fillRange(0, vals.length, 0);
      if (inx && iny) {
        final cgx = gx - dx, cgy = gy - dy;
        for (final sx in [-e, e]) {
          for (final sy in [-e, e]) {
            add(cgx + sx, cgy + sy, 0.25);
          }
        }
      } else if (inx) {
        final t = (dx + e) / (2 * e);
        add(gx - dx - e, gy, 1 - t);
        add(gx - dx + e, gy, t);
      } else {
        final t = (dy + e) / (2 * e);
        add(gx, gy - dy - e, 1 - t);
        add(gx, gy - dy + e, t);
      }
      for (var c = 0; c < planes.length; c++) {
        out[c].data[y * w + x] = vals[c].clamp(0, 255).toInt().toDouble();
      }
    }
  }
  return (out, (x0, y0, x1, y1));
}

// ---------------------------------------------------------------------------
// Growth area

/// The round gel: edge points of the chroma image (gel is more tinted than
/// the film) vote for a centre one radius inwards, at sizes 0.85–1.15 × the
/// nominal 50.5 mm; the strongest vote wins. Colony edges vote in scattered
/// places, so crowded plates do not upset it.
Plate findGrowthArea(List<GrayImage> lab, double mmPerPx) {
  final w = lab[0].width, h = lab[0].height;
  final chroma = GrayImage(w, h);
  for (var i = 0; i < chroma.data.length; i++) {
    final a = lab[1].data[i] - 128, b = lab[2].data[i] - 128;
    chroma.data[i] = math.sqrt(a * a + b * b);
  }
  final rNom = kNominalAreaDiameterMm / 2 / mmPerPx;
  final s = math.min(1.0, 60.0 / rNom);
  final sw = math.max(1, (w * s).round()), sh = math.max(1, (h * s).round());
  final small = chroma.resize(sw, sh).gaussianBlur(1.5);
  final (gx, gy) = sobel3(small);
  final mag = Float64List(sw * sh);
  for (var i = 0; i < mag.length; i++) {
    mag[i] = math.sqrt(gx[i] * gx[i] + gy[i] * gy[i]);
  }
  final thr = percentileSorted(List.of(mag)..sort(), 90);
  final vx = <double>[], vy = <double>[], ux = <double>[], uy = <double>[];
  final wgt = <double>[];
  for (var i = 0; i < mag.length; i++) {
    if (mag[i] <= thr) continue;
    vx.add((i % sw).toDouble());
    vy.add((i ~/ sw).toDouble());
    // Towards more chroma: inwards.
    ux.add(gx[i] / mag[i]);
    uy.add(gy[i] / mag[i]);
    wgt.add(mag[i]);
  }
  var best = (-1.0, 0.0, 0.0, 0.0);
  for (var fi = 0; fi < 13; fi++) {
    final r = rNom * s * (0.85 + fi * 0.025);
    final acc = GrayImage(sw, sh);
    for (var k = 0; k < vx.length; k++) {
      final ix = (vx[k] + ux[k] * r).round(), iy = (vy[k] + uy[k] * r).round();
      if (ix >= 0 && ix < sw && iy >= 0 && iy < sh) {
        acc.data[iy * sw + ix] += wgt[k];
      }
    }
    final sm = acc.gaussianBlur(1.5);
    var top = 0;
    for (var i = 1; i < sm.data.length; i++) {
      if (sm.data[i] > sm.data[top]) top = i;
    }
    // Normalised by circumference so larger circles do not win by size alone.
    final v = sm.data[top] / r;
    if (v > best.$1) best = (v, (top % sw) / s, (top ~/ sw) / s, r / s);
  }
  if (best.$1 <= 0) throw StateError('No growth area found');
  final (cx, cy, r) = _refineEdge(chroma, best.$2, best.$3, best.$4);
  return Plate(cx, cy, r, diameterMm: 2 * r * mmPerPx);
}

/// Sub-pixel circle from the strongest chroma drop on 90 rays near r.
(double, double, double) _refineEdge(
  GrayImage chroma,
  double cx,
  double cy,
  double r,
) {
  // Blur only the part the rays reach (plus the blur's own reach).
  final m = r * 1.1 + 12;
  final bx0 = math.max(0, (cx - m).floor()),
      bx1 = math.min(chroma.width, (cx + m).ceil() + 1);
  final by0 = math.max(0, (cy - m).floor()),
      by1 = math.min(chroma.height, (cy + m).ceil() + 1);
  if (bx1 - bx0 < 2 || by1 - by0 < 2) return (cx, cy, r);
  final crop = GrayImage(bx1 - bx0, by1 - by0);
  for (var y = by0; y < by1; y++) {
    for (var x = bx0; x < bx1; x++) {
      crop.data[(y - by0) * crop.width + x - bx0] = chroma.at(x, y);
    }
  }
  final sm = crop.gaussianBlur(1.5);
  final nt = ((r * 0.2) / 0.5).ceil();
  final ex = <double>[], ey = <double>[], rho = <double>[];
  for (var k = 0; k < 90; k++) {
    final a = 2 * math.pi * k / 90;
    final ca = math.cos(a), sa = math.sin(a);
    var prev = 0.0, bestD = double.infinity, bestK = 0;
    for (var j = 0; j < nt; j++) {
      final t = r * 0.9 + j * 0.5;
      final v = sampleBilinear(sm, cx + ca * t - bx0, cy + sa * t - by0);
      // Steepest drop going outwards.
      if (j > 0 && v - prev < bestD) {
        bestD = v - prev;
        bestK = j - 1;
      }
      prev = v;
    }
    final p = r * 0.9 + bestK * 0.5 + 0.25;
    rho.add(p);
    ex.add(cx + ca * p);
    ey.add(cy + sa * p);
  }
  final med = median(List.of(rho));
  final keep = [for (final p in rho) (p - med).abs() < math.max(3.0, 0.02 * r)];
  if (keep.where((k) => k).length < 20) return (cx, cy, r);
  final (fx, fy, fr) = fitCircle(ex, ey, keep);
  if (fr.isNaN ||
      math.sqrt((fx - cx) * (fx - cx) + (fy - cy) * (fy - cy)) > 0.1 * r ||
      (fr / r - 1).abs() > 0.1) {
    return (cx, cy, r);
  }
  return (fx, fy, fr);
}

// ---------------------------------------------------------------------------
// Gas bubbles

const double kBubbleMinRadiusMm = 0.28;
const double kBubbleMaxRadiusMm = 0.9;

/// The rim is thin: radii must be about a pixel apart.
const double kBubbleRadiusStepPx = 0.75;

/// Lab L (8-bit): rim brighter than inside and outside.
const double kBubbleMinScore = 8.0;

/// Sorted sector index that must still pass: 2 lets two of the 8 sectors
/// fail, e.g. where the bubble touches its colony.
const int kBubbleSectorIndex = 2;

/// Gas bubbles: a thin rim brighter than both its inside and outside, all
/// round. Only searched near colonies (gas counts within one colony
/// diameter), which also keeps it fast.
List<Bubble> findBubbles(
  GrayImage lightness,
  Plate plate,
  double mmPerPx,
  List<Colony> colonies,
) {
  final x0 = math.max(0, (plate.cx - plate.radius).toInt()),
      x1 = math.min(lightness.width, (plate.cx + plate.radius).toInt() + 1);
  final y0 = math.max(0, (plate.cy - plate.radius).toInt()),
      y1 = math.min(lightness.height, (plate.cy + plate.radius).toInt() + 1);
  final rw = x1 - x0, rh = y1 - y0;
  if (rw <= 0 || rh <= 0) return [];
  final crop = GrayImage(rw, rh);
  for (var y = 0; y < rh; y++) {
    for (var x = 0; x < rw; x++) {
      crop.data[y * rw + x] = lightness.at(x + x0, y + y0);
    }
  }
  final roi = crop.gaussianBlur(0.8);

  // Pixels inside the plate and near a colony.
  final near = Uint8List(rw * rh);
  final reach = kBubbleMaxRadiusMm / mmPerPx + 2;
  for (final c in colonies) {
    final d = 3 * c.radiusPx + reach;
    final ya = math.max(0, (c.y - d - y0).floor()),
        yb = math.min(rh - 1, (c.y + d - y0).ceil());
    final xa = math.max(0, (c.x - d - x0).floor()),
        xb = math.min(rw - 1, (c.x + d - x0).ceil());
    for (var y = ya; y <= yb; y++) {
      for (var x = xa; x <= xb; x++) {
        final ddx = x + x0 - c.x, ddy = y + y0 - c.y;
        if (ddx * ddx + ddy * ddy <= d * d) near[y * rw + x] = 1;
      }
    }
  }
  final rIn = plate.radius * 0.97;
  final idx = <int>[];
  for (var y = 0; y < rh; y++) {
    for (var x = 0; x < rw; x++) {
      final i = y * rw + x;
      if (near[i] == 0) continue;
      final ddx = x + x0 - plate.cx, ddy = y + y0 - plate.cy;
      if (math.sqrt(ddx * ddx + ddy * ddy) < rIn) idx.add(i);
    }
  }

  final best = Float64List(rw * rh), bestR = Float64List(rw * rh);
  final sectors = Float64List(kRingSectors);
  final r0 = kBubbleMinRadiusMm / mmPerPx, r1 = kBubbleMaxRadiusMm / mmPerPx;
  final nr = ((r1 - r0) / kBubbleRadiusStepPx).ceil();
  for (var k = 0; k < nr; k++) {
    final r = r0 + k * kBubbleRadiusStepPx;
    final taps = RingTaps(r);
    for (final i in idx) {
      taps.ridgeSectorsAt(roi, i % rw, i ~/ rw, sectors);
      final score = sectors[kBubbleSectorIndex]; // bright rim only
      if (score > best[i]) {
        best[i] = score;
        bestR[i] = r;
      }
    }
  }
  final cand =
      [
        for (final i in idx)
          if (best[i] >= kBubbleMinScore) i,
      ]..sort((a, b) {
        final c = best[b].compareTo(best[a]);
        return c != 0 ? c : a.compareTo(b);
      });
  final out = <Bubble>[];
  for (final i in cand) {
    final x = (i % rw + x0).toDouble(), y = (i ~/ rw + y0).toDouble();
    final r = bestR[i];
    var clash = false;
    for (final (bx, by, br) in out) {
      if (math.sqrt((x - bx) * (x - bx) + (y - by) * (y - by)) <
          math.max(r, br) * 1.5) {
        clash = true;
        break;
      }
    }
    if (!clash) out.add((x, y, r));
  }
  return out;
}

// ---------------------------------------------------------------------------
// Whole plate

const double kMoldMinRadiusMm = 1.0;

/// Lab b* (blue colonies are clearly negative).
const double kBlueMaxB = -8.0;

/// Lab b* rise in the zone around a colony.
const double kYellowMinDb = 10.0;

/// Decodes a photo, counts a downscaled copy and returns results in the
/// photo's full-resolution pixels. Takes a record so it can run in `compute`.
FilmResult countPetrifilmInPhoto((Uint8List, String) job) {
  final decoded = img.decodeImage(job.$1);
  if (decoded == null) throw const FormatException('Unsupported image');
  final photo = img.bakeOrientation(decoded);
  final s = math.min(1.0, kWorkShortSide / math.min(photo.width, photo.height));
  final work = s < 1
      ? img.copyResize(
          photo,
          width: (photo.width * s).round(),
          height: (photo.height * s).round(),
          interpolation: img.Interpolation.average,
        )
      : photo;
  final res = countPetrifilm(work, job.$2);
  return s < 1 ? res.scaled(1 / s) : res;
}

/// Counts a (work-size) film photo of [type] (a key of [kFilmTypes]).
FilmResult countPetrifilm(
  img.Image image,
  String type, {
  Plate? plate,
  FilmGrid? grid,
}) {
  final ft = kFilmTypes[type]!;
  final rgb = _rgbPlanes(image);
  final w = image.width, h = image.height;
  final gray = _gray(rgb);
  final g = grid ?? findGrid(gray);
  final mm = g.mmPerPx;
  final flags = <String>[];
  final rawLab = _lab(rgb);
  final area = plate ?? findGrowthArea(rawLab, mm);
  final p = Plate(
    area.cx,
    area.cy,
    area.radius,
    diameterMm: 2 * area.radius * mm,
  );
  final (clean, (bx0, by0, bx1, by1)) = fillGridLines(rgb, g, g.lineHalfPx, p);
  final lab = [for (final c in rawLab) c.copy()];
  _labInto(clean, lab, bx0, by0, bx1, by1);
  if ((p.diameterMm / kNominalAreaDiameterMm - 1).abs() > 0.1) {
    flags.add('area_size_unexpected');
  }

  // Wide background where large features (molds, yellow zones) would lift it.
  final kernel = (type == 'ym' || type == 'eb') ? 12.0 : 6.0;
  final bg = [for (final c in lab) estimateBackground(c, p, kernelMm: kernel)];
  final fg = GrayImage(w, h);
  for (var i = 0; i < fg.data.length; i++) {
    final dL = lab[0].data[i] - bg[0].data[i];
    if (dL >= 0) continue;
    final da = lab[1].data[i] - bg[1].data[i];
    final db = lab[2].data[i] - bg[2].data[i];
    fg.data[i] = -dL + 0.5 * math.sqrt(da * da + db * db);
  }
  final mask = p.mask(w, h, rimFraction: 0.95);
  // Molds are large and touch: much higher limits before a blob is a
  // "spreader" or the plate is too crowded.
  final params = DetectParams(
    minDiameterMm: 0.25,
    kSigma: 4.0,
    minContrast: 8.0,
    spreaderFraction: type == 'ym' ? 0.25 : 0.04,
  );
  final det = detect(fg, mask, mm, params);

  var bubbles = <Bubble>[];
  if (type == 'ec' || type == 'cc' || type == 'eb') {
    // A bright ring centred on a colony is its yellow zone or edge, not gas.
    // On the original image: erasing a grid line also erases the stretch of
    // a bubble's bright rim it crosses, while the thin printed line only
    // dims it.
    bubbles = [
      for (final b in findBubbles(rawLab[0], p, mm, det.colonies))
        if (!det.colonies.any(
          (c) => _dist(b.$1, b.$2, c.x, c.y) < c.radiusPx + 0.5 * b.$3,
        ))
          b,
    ];
  }
  var marks = _cleanMarks(det.colonies, bubbles, mm);
  if (type == 'ym') {
    marks = _mergeSplitMolds(_ownRadius(marks, fg, mask, det.threshold), mm);
    marks = [...marks, ..._yeastsInMolds(fg, marks, mm, params)];
  }
  final colonies = <FilmColony>[];
  for (final c in marks) {
    final rIn = math.max(1.0, 0.6 * c.radiusPx);
    final b = _discMean(lab[2], c.x, c.y, rIn);
    final String kind;
    if (type == 'ac') {
      kind = 'colony';
    } else if (type == 'ym') {
      kind = c.radiusPx * mm >= kMoldMinRadiusMm ? 'mold' : 'yeast';
    } else {
      kind = (b - 128) < kBlueMaxB ? 'blue' : 'red';
    }
    final gas = bubbles.any(
      (bb) =>
          _dist(c.x, c.y, bb.$1, bb.$2) - c.radiusPx - bb.$3 <= 2 * c.radiusPx,
    );
    var yellow = false;
    if (type == 'eb') {
      final ringB = _ringMean(
        lab[2],
        c.x,
        c.y,
        c.radiusPx + 0.3 / mm,
        c.radiusPx + 1.5 / mm,
      );
      yellow =
          ringB - _discMean(bg[2], c.x, c.y, math.max(c.radiusPx, 1.0)) >=
          kYellowMinDb;
    }
    colonies.add(
      FilmColony(c.x, c.y, c.radiusPx, kind, n: c.n, gas: gas, yellow: yellow),
    );
  }

  bool rule(String result, FilmColony c) => switch (result) {
    'aerobic' => true,
    'ecoli' => c.kind == 'blue',
    'coliform' =>
      type == 'ec' ? c.kind == 'blue' || (c.kind == 'red' && c.gas) : c.gas,
    'enterobacteriaceae' => c.kind == 'red' && (c.gas || c.yellow),
    'yeast' => c.kind == 'yeast',
    'mold' => c.kind == 'mold',
    _ => false,
  };

  final counts = {
    for (final k in ft.results)
      k: colonies.where((c) => rule(k, c)).fold(0, (s, c) => s + c.n),
  };

  Map<String, double>? estimates;
  var used = 0;
  if (counts.values.reduce(math.max) > ft.countMax) {
    final squares = _completeSquares(g, p);
    used = squares.length;
    if (used >= 3) {
      estimates = {};
      for (final k in ft.results) {
        var total = 0;
        for (final sq in squares) {
          for (final c in colonies) {
            if (rule(k, c) && _inSquare(g, sq, c.x, c.y)) total += c.n;
          }
        }
        estimates[k] = total / used * ft.areaCm2;
      }
      flags.add('estimated');
    }
  }
  if (det.coverage > (type == 'ym' ? 0.6 : 0.3)) flags.add('tntc');
  if (det.spreaders > 0) flags.add('spreader');
  return FilmResult(
    type: type,
    plate: p,
    grid: g,
    colonies: colonies,
    bubbles: bubbles,
    counts: counts,
    estimates: estimates,
    squaresUsed: used,
    flags: flags,
  );
}

double _dist(double x0, double y0, double x1, double y1) =>
    math.sqrt((x0 - x1) * (x0 - x1) + (y0 - y1) * (y0 - y1));

/// Marks largest first; equal radii keep their order.
List<Colony> _largestFirst(List<Colony> marks) {
  final order = List.generate(marks.length, (i) => i)
    ..sort((a, b) {
      final c = marks[b].radiusPx.compareTo(marks[a].radiusPx);
      return c != 0 ? c : a.compareTo(b);
    });
  return [for (final i in order) marks[i]];
}

/// Each mark's own size: the distance-transform value at its centre. The
/// detector gives the marks it splits out of one blob a shared radius, which
/// would make a yeast touching a mold look as large as the mold.
List<Colony> _ownRadius(
  List<Colony> marks,
  GrayImage fg,
  Uint8List mask,
  double threshold,
) {
  final w = fg.width, h = fg.height;
  final binary = Uint8List(w * h);
  for (var i = 0; i < binary.length; i++) {
    binary[i] = fg.data[i] > threshold && mask[i] > 0 ? 1 : 0;
  }
  final dt = edt(binary, w, h);
  return [
    for (final c in marks)
      () {
        final x = c.x.round(), y = c.y.round();
        var r = 0.0;
        for (var yy = math.max(0, y - 1); yy < math.min(h, y + 2); yy++) {
          for (var xx = math.max(0, x - 1); xx < math.min(w, x + 2); xx++) {
            r = math.max(r, dt[yy * w + xx]);
          }
        }
        return Colony(
          c.x,
          c.y,
          r > 0 ? math.max(1.0, math.min(c.radiusPx, r)) : c.radiusPx,
          n: c.n,
          score: c.score,
        );
      }(),
  ];
}

/// A mold's diffuse body can give two marks inside its own radius: keep one.
List<Colony> _mergeSplitMolds(List<Colony> marks, double mm) {
  final out = <Colony>[];
  for (final c in _largestFirst(marks)) {
    final big = c.radiusPx * mm >= kMoldMinRadiusMm;
    if (big &&
        out.any(
          (o) =>
              o.radiusPx * mm >= kMoldMinRadiusMm &&
              _dist(c.x, c.y, o.x, o.y) < 0.9 * o.radiusPx,
        )) {
      continue;
    }
    out.add(c);
  }
  return out;
}

/// Yeasts touching a mold merge into its diffuse edge. Finds compact dots in
/// a high-pass of the contrast inside each mold, away from its centre.
List<Colony> _yeastsInMolds(
  GrayImage fg,
  List<Colony> marks,
  double mm,
  DetectParams params,
) {
  final molds = [
    for (final m in marks)
      if (m.radiusPx * mm >= kMoldMinRadiusMm) m,
  ];
  if (molds.isEmpty) return [];
  final w = fg.width, h = fg.height;
  final blur = fg.gaussianBlur(0.5 / mm);
  final hp = GrayImage(w, h);
  for (var i = 0; i < hp.data.length; i++) {
    hp.data[i] = math.max(0, fg.data[i] - blur.data[i]);
  }
  final region = Uint8List(w * h);
  for (final m in molds) {
    final cx = m.x.round(), cy = m.y.round(), r = (m.radiusPx * 1.3).round();
    for (var y = math.max(0, cy - r); y <= math.min(h - 1, cy + r); y++) {
      for (var x = math.max(0, cx - r); x <= math.min(w - 1, cx + r); x++) {
        if ((x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r) {
          region[y * w + x] = 1;
        }
      }
    }
  }
  final found = detect(hp, region, mm, params).colonies;
  final out = <Colony>[];
  for (final c in found) {
    if (c.radiusPx * mm >= kMoldMinRadiusMm) continue;
    if (molds.any((m) => _dist(c.x, c.y, m.x, m.y) < 0.5 * m.radiusPx)) {
      continue;
    }
    if (marks.any(
      (o) =>
          o.radiusPx * mm < kMoldMinRadiusMm &&
          _dist(c.x, c.y, o.x, o.y) < math.max(o.radiusPx, c.radiusPx),
    )) {
      continue;
    }
    out.add(Colony(c.x, c.y, c.radiusPx, score: c.score));
  }
  return out;
}

/// Drops specks on a bubble's dark outline, and merges marks that coincide.
List<Colony> _cleanMarks(
  List<Colony> colonies,
  List<Bubble> bubbles,
  double mm,
) {
  final out = <Colony>[];
  for (final c in _largestFirst(colonies)) {
    if (c.radiusPx * mm < 0.3 &&
        bubbles.any(
          (b) => (_dist(c.x, c.y, b.$1, b.$2) - b.$3).abs() < 0.25 / mm,
        )) {
      continue;
    }
    if (out.any((o) => _dist(c.x, c.y, o.x, o.y) < 0.5 * o.radiusPx)) {
      continue;
    }
    out.add(c);
  }
  return out;
}

/// Mean of [ch] over the disc of radius [r] at (x, y).
double _discMean(GrayImage ch, double x, double y, double r) {
  final w = ch.width, h = ch.height;
  final x0 = math.max(0, (x - r).toInt()),
      x1 = math.min(w, (x + r).toInt() + 1);
  final y0 = math.max(0, (y - r).toInt()),
      y1 = math.min(h, (y + r).toInt() + 1);
  var s = 0.0;
  var n = 0;
  for (var yy = y0; yy < y1; yy++) {
    for (var xx = x0; xx < x1; xx++) {
      if (_dist(xx.toDouble(), yy.toDouble(), x, y) <= r) {
        s += ch.data[yy * w + xx];
        n++;
      }
    }
  }
  return n > 0 ? s / n : ch.at(x.toInt(), y.toInt());
}

/// Mean of [ch] over the ring r0..r1 around (x, y).
double _ringMean(GrayImage ch, double x, double y, double r0, double r1) {
  final w = ch.width, h = ch.height;
  final x0 = math.max(0, (x - r1).toInt()),
      x1 = math.min(w, (x + r1).toInt() + 1);
  final y0 = math.max(0, (y - r1).toInt()),
      y1 = math.min(h, (y + r1).toInt() + 1);
  var s = 0.0;
  var n = 0;
  for (var yy = y0; yy < y1; yy++) {
    for (var xx = x0; xx < x1; xx++) {
      final d = _dist(xx.toDouble(), yy.toDouble(), x, y);
      if (d >= r0 && d <= r1) {
        s += ch.data[yy * w + xx];
        n++;
      }
    }
  }
  return n > 0 ? s / n : 0;
}

/// Grid squares (i, j) lying wholly inside the counted area.
List<(int, int)> _completeSquares(FilmGrid grid, Plate plate) {
  final (gx, gy) = grid.toGrid(plate.cx, plate.cy);
  final p = grid.pitchPx;
  final n = (plate.radius / p).toInt() + 2;
  final i0 = ((gx - grid.ox) / p).floor(), j0 = ((gy - grid.oy) / p).floor();
  final out = <(int, int)>[];
  for (var i = i0 - n; i <= i0 + n; i++) {
    for (var j = j0 - n; j <= j0 + n; j++) {
      var all = true;
      for (final a in const [0, 1]) {
        for (final b in const [0, 1]) {
          final (x, y) = grid.toImage(
            grid.ox + (i + a) * p,
            grid.oy + (j + b) * p,
          );
          if (_dist(x, y, plate.cx, plate.cy) >= plate.radius * 0.95) {
            all = false;
          }
        }
      }
      if (all) out.add((i, j));
    }
  }
  return out;
}

bool _inSquare(FilmGrid grid, (int, int) sq, double x, double y) {
  final (gx, gy) = grid.toGrid(x, y);
  return ((gx - grid.ox) / grid.pitchPx).floor() == sq.$1 &&
      ((gy - grid.oy) / grid.pitchPx).floor() == sq.$2;
}
