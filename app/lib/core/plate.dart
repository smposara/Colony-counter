import 'dart:math' as math;
import 'dart:typed_data';

import 'gray_image.dart';

const double kDefaultPlateDiameterMm = 90.0;

enum PlateShape { round, square }

/// Corner radius of square plates as a fraction of the half-side.
const double kSquareCorner = 0.12;

/// Dishes and filters the app can count. [sizeMm] is the nominal diameter (or
/// side, for square plates) of the edge the plate finder locks onto.
enum PlateFormat {
  dish90('90 mm dish', PlateShape.round, 90),
  dish60('60 mm dish', PlateShape.round, 60),
  dish100('100 mm dish', PlateShape.round, 100),
  dish150('150 mm dish', PlateShape.round, 150),
  square100('100 mm square plate', PlateShape.square, 100),
  square120('120 mm square plate', PlateShape.square, 120),

  /// A gridded membrane filter (water testing); the counted area is the filter.
  membrane47('47 mm membrane filter', PlateShape.round, 47, membrane: true);

  const PlateFormat(
    this.label,
    this.shape,
    this.sizeMm, {
    this.membrane = false,
  });

  final String label;
  final PlateShape shape;
  final double sizeMm;
  final bool membrane;

  static PlateFormat byName(String? name) => PlateFormat.values.firstWhere(
    (f) => f.name == name,
    orElse: () => PlateFormat.dish90,
  );
}

/// A plate in image pixel coordinates: a circle, or a square of half-side
/// [radius] turned by [angle] radians.
class Plate {
  const Plate(
    this.cx,
    this.cy,
    this.radius, {
    this.diameterMm = kDefaultPlateDiameterMm,
    this.shape = PlateShape.round,
    this.angle = 0,
  });

  final double cx;
  final double cy;

  /// Radius of a round plate; half the side of a square one.
  final double radius;

  /// Diameter of a round plate; side of a square one.
  final double diameterMm;
  final PlateShape shape;

  /// Rotation of a square plate (radians).
  final double angle;

  bool get isSquare => shape == PlateShape.square;

  double get mmPerPx => diameterMm / (2 * radius);

  Plate scaled(double s) => Plate(
    cx * s,
    cy * s,
    radius * s,
    diameterMm: diameterMm,
    shape: shape,
    angle: angle,
  );

  Plate copyWith({double? cx, double? cy, double? radius, double? angle}) =>
      Plate(
        cx ?? this.cx,
        cy ?? this.cy,
        radius ?? this.radius,
        diameterMm: diameterMm,
        shape: shape,
        angle: angle ?? this.angle,
      );

  /// Whether image point (x, y) is inside the counted area.
  bool contains(double x, double y, {double rimFraction = 1}) {
    final dx = x - cx, dy = y - cy;
    final r = radius * rimFraction;
    if (!isSquare) return dx * dx + dy * dy <= r * r;
    final c = math.cos(angle), s = math.sin(angle);
    final u = (dx * c + dy * s).abs(), v = (-dx * s + dy * c).abs();
    if (u > r || v > r) return false;
    // Square dishes have rounded corners, where the wall's edge would
    // otherwise be counted.
    final k = r - kSquareCorner * r;
    if (u <= k || v <= k) return true;
    return (u - k) * (u - k) + (v - k) * (v - k) <=
        math.pow(kSquareCorner * r, 2);
  }

  /// Corners of a square plate (or a 64-gon for a round one) at [rimFraction].
  List<(double, double)> outline({double rimFraction = 1}) {
    final r = radius * rimFraction;
    if (!isSquare) {
      return [
        for (var k = 0; k < 64; k++)
          (
            cx + r * math.cos(2 * math.pi * k / 64),
            cy + r * math.sin(2 * math.pi * k / 64),
          ),
      ];
    }
    final c = math.cos(angle), s = math.sin(angle);
    final k = r * (1 - kSquareCorner), cr = r * kSquareCorner;
    final pts = <(double, double)>[];
    // Rounded corners, clockwise from the top-left.
    for (final (su, sv, a0) in const [
      (-1, -1, math.pi),
      (1, -1, 1.5 * math.pi),
      (1, 1, 0.0),
      (-1, 1, 0.5 * math.pi),
    ]) {
      for (var i = 0; i <= 6; i++) {
        final a = a0 + i / 6 * math.pi / 2;
        final u = su * k + cr * math.cos(a), v = sv * k + cr * math.sin(a);
        pts.add((cx + u * c - v * s, cy + u * s + v * c));
      }
    }
    return pts;
  }

  /// 1 inside the counted area (radius x [rimFraction]), 0 outside.
  Uint8List mask(int width, int height, {double rimFraction = 0.95}) {
    final m = Uint8List(width * height);
    final r = radius * rimFraction;
    if (isSquare) {
      final reach = r * math.sqrt2;
      final y0 = math.max(0, (cy - reach).floor()),
          y1 = math.min(height - 1, (cy + reach).ceil());
      final x0 = math.max(0, (cx - reach).floor()),
          x1 = math.min(width - 1, (cx + reach).ceil());
      for (var y = y0; y <= y1; y++) {
        for (var x = x0; x <= x1; x++) {
          if (contains(x.toDouble(), y.toDouble(), rimFraction: rimFraction)) {
            m[y * width + x] = 1;
          }
        }
      }
      return m;
    }
    final r2 = r * r;
    final y0 = math.max(0, (cy - r).floor()),
        y1 = math.min(height - 1, (cy + r).ceil());
    for (var y = y0; y <= y1; y++) {
      final dy = y - cy;
      final rem = r2 - dy * dy;
      if (rem < 0) continue;
      final half = math.sqrt(rem);
      final x0 = math.max(0, (cx - half).ceil()),
          x1 = math.min(width - 1, (cx + half).floor());
      for (var x = x0; x <= x1; x++) {
        m[y * width + x] = 1;
      }
    }
    return m;
  }

  Map<String, dynamic> toJson() => {
    'cx': cx,
    'cy': cy,
    'radius': radius,
    'diameter_mm': diameterMm,
    if (isSquare) 'shape': shape.name,
    if (angle != 0) 'angle': angle,
  };

  factory Plate.fromJson(Map<String, dynamic> j) => Plate(
    (j['cx'] as num).toDouble(),
    (j['cy'] as num).toDouble(),
    (j['radius'] as num).toDouble(),
    diameterMm:
        (j['diameter_mm'] as num?)?.toDouble() ?? kDefaultPlateDiameterMm,
    shape: j['shape'] == 'square' ? PlateShape.square : PlateShape.round,
    angle: (j['angle'] as num?)?.toDouble() ?? 0,
  );
}

/// Edge map of a small copy of the image, used by the plate finders.
class _Edges {
  _Edges(GrayImage image, int workSize)
    : scale = workSize / math.max(image.width, image.height) {
    final small = image
        .resize((image.width * scale).round(), (image.height * scale).round())
        .gaussianBlur(1.2);
    w = small.width;
    h = small.height;
    gx = Float32List(w * h);
    gy = Float32List(w * h);
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        final i = y * w + x;
        gx[i] = (small.data[i + 1] - small.data[i - 1]) / 2;
        gy[i] = (small.data[i + w] - small.data[i - w]) / 2;
      }
    }
  }

  final double scale;
  late final int w, h;
  late final Float32List gx, gy;

  double get short => math.min(w, h).toDouble();

  /// Mean |gradient across the edge| at (x, y) for edge normal (nx, ny); 0
  /// outside the image, so shapes that leave the image score lower.
  double _at(double x, double y, double nx, double ny) {
    final xi = x.round(), yi = y.round();
    if (xi < 1 || yi < 1 || xi >= w - 1 || yi >= h - 1) return 0;
    final i = yi * w + xi;
    return (gx[i] * nx + gy[i] * ny).abs();
  }

  double circle(double cx, double cy, double r) {
    const n = 120;
    var s = 0.0;
    for (var k = 0; k < n; k++) {
      final a = 2 * math.pi * k / n;
      final c = math.cos(a), sn = math.sin(a);
      s += _at(cx + r * c, cy + r * sn, c, sn);
    }
    return s / n;
  }

  /// Square of half-side [r] turned by [angle]. Corners are skipped because
  /// square dishes have rounded ones.
  double square(double cx, double cy, double r, double angle) {
    const perSide = 30;
    final c = math.cos(angle), sn = math.sin(angle);
    var s = 0.0;
    for (final (nu, nv) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
      // Edge normal in image coordinates.
      final nx = nu * c - nv * sn, ny = nu * sn + nv * c;
      for (var k = 0; k < perSide; k++) {
        final t = (-0.8 + 1.6 * k / (perSide - 1)) * r;
        // Point on the side: centre + r·normal + t·tangent.
        final x = cx + r * nx - t * ny, y = cy + r * ny + t * nx;
        s += _at(x, y, nx, ny);
      }
    }
    return s / (4 * perSide);
  }
}

typedef _Fit = ({double score, double cx, double cy, double r, double a});

/// Best circle near ([cx0], [cy0]) by a three-stage coarse-to-fine search.
_Fit _fitCircle(
  _Edges e,
  double cx0,
  double cy0,
  double cRange,
  double rMin,
  double rMax,
) {
  final short = e.short;
  _Fit best = (score: -1, cx: cx0, cy: cy0, r: rMin, a: 0);
  void search(
    double cx0,
    double cy0,
    double cRange,
    double cStep,
    double r0,
    double r1,
    double rStep,
  ) {
    for (var cy = cy0 - cRange; cy <= cy0 + cRange; cy += cStep) {
      for (var cx = cx0 - cRange; cx <= cx0 + cRange; cx += cStep) {
        for (var r = r0; r <= r1; r += rStep) {
          final s = e.circle(cx, cy, r);
          if (s > best.score) best = (score: s, cx: cx, cy: cy, r: r, a: 0);
        }
      }
    }
  }

  search(cx0, cy0, cRange, short * 0.02, rMin, rMax, short * 0.01);
  final b1 = best;
  search(
    b1.cx,
    b1.cy,
    short * 0.02,
    1,
    b1.r - short * 0.01,
    b1.r + short * 0.01,
    0.5,
  );
  final b2 = best;
  search(b2.cx, b2.cy, 1, 0.25, b2.r - 1, b2.r + 1, 0.25);
  return best;
}

/// Best square (half-side, angle within ±20°) near the image centre.
_Fit _fitSquare(_Edges e, double rMin, double rMax) {
  final short = e.short;
  _Fit best = (score: -1, cx: e.w / 2, cy: e.h / 2, r: rMin, a: 0);
  const deg = math.pi / 180;
  void search(
    double cx0,
    double cy0,
    double cRange,
    double cStep,
    double r0,
    double r1,
    double rStep,
    double a0,
    double aRange,
    double aStep,
  ) {
    for (var cy = cy0 - cRange; cy <= cy0 + cRange; cy += cStep) {
      for (var cx = cx0 - cRange; cx <= cx0 + cRange; cx += cStep) {
        for (var r = r0; r <= r1; r += rStep) {
          for (var a = a0 - aRange; a <= a0 + aRange + 1e-9; a += aStep) {
            final s = e.square(cx, cy, r, a);
            if (s > best.score) best = (score: s, cx: cx, cy: cy, r: r, a: a);
          }
        }
      }
    }
  }

  search(
    e.w / 2,
    e.h / 2,
    short * 0.16,
    short * 0.02,
    rMin,
    rMax,
    short * 0.01,
    0,
    20 * deg,
    4 * deg,
  );
  final b1 = best;
  search(
    b1.cx,
    b1.cy,
    short * 0.02,
    1,
    b1.r - short * 0.01,
    b1.r + short * 0.01,
    0.5,
    b1.a,
    4 * deg,
    1 * deg,
  );
  final b2 = best;
  search(
    b2.cx,
    b2.cy,
    1,
    0.5,
    b2.r - 1,
    b2.r + 1,
    0.25,
    b2.a,
    1 * deg,
    0.25 * deg,
  );
  return best;
}

Plate _toPlate(_Fit f, _Edges e, PlateFormat format) => Plate(
  f.cx / e.scale,
  f.cy / e.scale,
  f.r / e.scale,
  diameterMm: format.sizeMm,
  shape: format.shape,
  angle: f.a,
);

/// Finds the dish as the circle (or square) with the strongest edge.
///
/// A coarse-to-fine search over centre and size on a small copy of the image,
/// scoring each shape by the mean |gradient| across its edge. Works for both
/// the lightbox (black surround) and freehand photos. [minFill] and [maxFill] bound
/// the dish size as a fraction of the image's shorter side.
Plate findPlate(
  GrayImage image, {
  PlateFormat format = PlateFormat.dish90,
  double minFill = 0.4,
  double maxFill = 1.1,
  int workSize = 320,
}) {
  final e = _Edges(image, workSize);
  final short = e.short;
  final rMin = short * minFill / 2, rMax = short * maxFill / 2;
  final best = format.shape == PlateShape.square
      ? _fitSquare(e, rMin, rMax)
      : _fitCircle(e, e.w / 2, e.h / 2, short * 0.2, rMin, rMax);
  if (best.score <= 0) {
    throw StateError('No plate found in image');
  }
  return _toPlate(best, e, format);
}

/// Finds several round plates of about the same size in one photo, in reading
/// order (top row first, left to right).
///
/// The strongest circle sets the size; further circles within ±20 % of it are
/// taken in order of edge strength while they don't overlap a plate already
/// found and their edge is at least [minRelativeScore] of the first one's.
List<Plate> findPlates(
  GrayImage image, {
  PlateFormat format = PlateFormat.dish90,
  int maxPlates = 12,
  double minFill = 0.12,
  double maxFill = 0.7,
  double minRelativeScore = 0.45,
  int workSize = 400,
}) {
  final e = _Edges(image, workSize);
  final short = e.short;
  final step = short * 0.02;

  // Best circle for every candidate centre within a radius band.
  List<_Fit> candidates(double r0, double r1) {
    final out = <_Fit>[];
    for (var cy = step; cy < e.h - step; cy += step) {
      for (var cx = step; cx < e.w - step; cx += step) {
        _Fit? best;
        for (var r = r0; r <= r1; r += short * 0.01) {
          final s = e.circle(cx, cy, r);
          if (best == null || s > best.score) {
            best = (score: s, cx: cx, cy: cy, r: r, a: 0);
          }
        }
        if (best != null) out.add(best);
      }
    }
    return out..sort((a, b) => b.score.compareTo(a.score));
  }

  final all = candidates(short * minFill / 2, short * maxFill / 2);
  if (all.isEmpty || all.first.score <= 0) {
    throw StateError('No plate found in image');
  }
  final first = _fitCircle(
    e,
    all.first.cx,
    all.first.cy,
    step,
    all.first.r * 0.9,
    all.first.r * 1.1,
  );
  final found = <_Fit>[first];
  bool overlaps(_Fit c) => found.any(
    (f) =>
        math.sqrt(math.pow(f.cx - c.cx, 2) + math.pow(f.cy - c.cy, 2)) <
        (f.r + c.r) * 0.9,
  );
  for (final c in candidates(first.r * 0.8, first.r * 1.2)) {
    if (found.length >= maxPlates) break;
    if (c.score < first.score * minRelativeScore) break;
    if (overlaps(c)) continue;
    final fit = _fitCircle(e, c.cx, c.cy, step, c.r * 0.95, c.r * 1.05);
    if (!overlaps(fit) && fit.score >= first.score * minRelativeScore) {
      found.add(fit);
    }
  }

  // Reading order: rows of plates whose centres are within a radius in y.
  found.sort((a, b) => a.cy.compareTo(b.cy));
  final rows = <List<_Fit>>[];
  for (final f in found) {
    if (rows.isNotEmpty && (f.cy - rows.last.first.cy).abs() < first.r) {
      rows.last.add(f);
    } else {
      rows.add([f]);
    }
  }
  return [
    for (final row in rows)
      for (final f in row..sort((a, b) => a.cx.compareTo(b.cx)))
        _toPlate(f, e, format),
  ];
}
