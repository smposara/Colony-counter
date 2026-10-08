import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'classical.dart';
import 'colour.dart';
import 'drop_stats.dart';
import 'gray_image.dart';
import 'normalize.dart';
import 'pipeline.dart';
import 'plate.dart';
import 'spots.dart';

/// Drop plates (Miles–Misra / spot plates): finding, labelling and counting
/// drops (mirrors ml/colonycounter/drops.py).
///
///     photo → plate → colonies (classical detector) and the foreground
///           → drop candidates: groups of nearby colonies, plus confluent lawns
///           → layout fit: the planned template (sectors or a grid), turned,
///             moved and scaled onto the candidates, gives every planned drop,
///             empty ones included
///           → labels: which way round the layout lies is chosen by how well
///             the counts follow the tenfold dilution series (Poisson
///             likelihood)
///           → per drop: colonies inside, confluent / crowded flags; colonies
///             outside every drop are strays and are not counted
///
/// Statistics and CFU/mL: drop_stats.dart.

/// A 10 µL drop on dried agar.
const double kReferenceDropMm = 7.0;

/// Foreground over this fraction of the drop: confluent.
const double kConfluentCover = 0.6;

/// Colonies over this fraction of the drop: crowded.
const double kCrowdedCover = 0.35;

/// Colonies belong to the nearest drop within this many drop radii.
const double kAssignRadius = 1.1;

/// How the drops were placed.
sealed class DropTemplate {
  const DropTemplate();
}

/// [n] drops on a ring of [ringMm], clockwise from the top, with
/// [dropsPerDilution] consecutive drops per dilution.
class SectorTemplate extends DropTemplate {
  const SectorTemplate({
    this.n = 8,
    this.ringMm = 25,
    this.dropsPerDilution = 1,
  });

  final int n;
  final double ringMm;
  final int dropsPerDilution;
}

/// [rows] × [cols] drops [pitchMm] apart: a row per dilution, a column per
/// replicate.
class GridTemplate extends DropTemplate {
  const GridTemplate({this.rows = 4, this.cols = 3, this.pitchMm = 11});

  final int rows;
  final int cols;
  final double pitchMm;
}

/// No template: drops are the colony groups, in reading order.
class FreeTemplate extends DropTemplate {
  const FreeTemplate();
}

/// Expected drop footprint: 7 mm for 10 µL, scaling with the cube root of the
/// volume (5 µL → 5.6 mm, 20 µL → 8.8 mm).
double dropDiameterMm(double volumeUl) =>
    kReferenceDropMm * math.pow(volumeUl / 10.0, 1 / 3);

typedef PlannedDrop = ({double x, double y, int dilutionExp, int replicate});

/// Planned drops in mm relative to the layout centre, image axes (y down).
List<PlannedDrop> templatePositionsMm(DropTemplate t, List<int> dilutions) {
  int dil(int i) => dilutions[math.min(i, dilutions.length - 1)];
  switch (t) {
    case SectorTemplate():
      final per = math.max(1, t.dropsPerDilution);
      return [
        for (var k = 0; k < t.n; k++)
          (
            x: t.ringMm * math.cos((-90 + 360 * k / t.n) * math.pi / 180),
            y: t.ringMm * math.sin((-90 + 360 * k / t.n) * math.pi / 180),
            dilutionExp: dil(k ~/ per),
            replicate: k % per + 1,
          ),
      ];
    case GridTemplate():
      return [
        for (var r = 0; r < t.rows; r++)
          for (var c = 0; c < t.cols; c++)
            (
              x: (c - (t.cols - 1) / 2) * t.pitchMm,
              y: (r - (t.rows - 1) / 2) * t.pitchMm,
              dilutionExp: dil(r),
              replicate: c + 1,
            ),
      ];
    case FreeTemplate():
      return const [];
  }
}

class DropCandidate {
  const DropCandidate(
    this.x,
    this.y,
    this.radiusPx,
    this.n, {
    this.confluent = false,
  });

  final double x;
  final double y;
  final double radiusPx;

  /// Colonies in the group.
  final int n;
  final bool confluent;
}

class FoundDrop {
  FoundDrop({
    required this.x,
    required this.y,
    required this.radiusPx,
    required this.position,
    required this.dilutionExp,
    required this.replicate,
    required this.count,
    this.confluent = false,
    this.crowded = false,
    this.colonies = const [],
  });

  final double x;
  final double y;
  final double radiusPx;

  /// Index in the template (null for a free drop).
  final int? position;
  final int dilutionExp;
  int replicate;

  /// Colonies inside (meaningless when confluent).
  final int count;
  final bool confluent;
  final bool crowded;

  /// Indices into [DropPlateResult.colonies].
  final List<int> colonies;

  bool get tntc => confluent;

  /// As a drop of the review screen: the circle that held its colonies
  /// (1.1 drop radii), its layout position and flags.
  Spot toSpot() => Spot(
    x,
    y,
    radiusPx * kAssignRadius,
    dilutionExp: dilutionExp,
    replicate: replicate,
    tntc: tntc,
    position: position,
    flags: [if (crowded) 'crowded'],
  );

  DropCount toCount() => DropCount(dilutionExp, replicate, count, tntc: tntc);

  FoundDrop scaled(double s) => FoundDrop(
    x: x * s,
    y: y * s,
    radiusPx: radiusPx * s,
    position: position,
    dilutionExp: dilutionExp,
    replicate: replicate,
    count: count,
    confluent: confluent,
    crowded: crowded,
    colonies: colonies,
  );
}

class LayoutFit {
  const LayoutFit(
    this.rotationDeg,
    this.scale,
    this.cx,
    this.cy,
    this.matched,
    this.outside,
  );

  final double rotationDeg;

  /// Fitted size / nominal size.
  final double scale;
  final double cx;
  final double cy;

  /// Candidates on a planned position.
  final int matched;

  /// Candidates on no planned position.
  final int outside;

  LayoutFit scaled(double s) =>
      LayoutFit(rotationDeg, scale, cx * s, cy * s, matched, outside);
}

class DropPlateResult {
  DropPlateResult({
    required this.plate,
    required this.drops,
    required this.colonies,
    required this.strays,
    required this.fit,
    required this.flags,
    this.imageWidth = 0,
    this.imageHeight = 0,
  });

  final Plate plate;
  final List<FoundDrop> drops;
  final List<Colony> colonies;

  /// Colonies in no drop.
  final List<int> strays;
  final LayoutFit? fit;

  /// `colonies_outside_drops`, `layout_uncertain`.
  final List<String> flags;
  final int imageWidth;
  final int imageHeight;

  double get mmPerPx => plate.mmPerPx;

  List<DropCount> get counts => [for (final d in drops) d.toCount()];

  DropPlateResult _copy({
    double s = 1,
    List<Colony>? colonies,
    int? imageWidth,
    int? imageHeight,
  }) => DropPlateResult(
    plate: plate.scaled(s),
    drops: [for (final d in drops) d.scaled(s)],
    colonies: colonies ?? [for (final c in this.colonies) c.scaled(s)],
    strays: strays,
    fit: fit?.scaled(s),
    flags: flags,
    imageWidth: imageWidth ?? this.imageWidth,
    imageHeight: imageHeight ?? this.imageHeight,
  );

  DropPlateResult scaled(double s) => _copy(s: s);

  /// The drops as the review screen keeps them, and the colonies to go with
  /// them. Where a crowded drop was counted by area above its marks, the
  /// largest mark in it stands for the difference (a merged cluster), so the
  /// drop's count can still be edited mark by mark.
  (List<Colony>, List<Spot>) toSpots() {
    final cols = List.of(colonies);
    for (final d in drops) {
      final marks = d.colonies.fold(0, (s, i) => s + cols[i].n);
      if (d.confluent || d.count <= marks || d.colonies.isEmpty) continue;
      final big = d.colonies.reduce(
        (a, b) => cols[a].radiusPx >= cols[b].radiusPx ? a : b,
      );
      cols[big] = cols[big].withN(cols[big].n + d.count - marks);
    }
    return (cols, [for (final d in drops) d.toSpot()]);
  }
}

// ---------------------------------------------------------------------------
// Candidates

/// Single-linkage groups: colonies whose gap is under 0.35 drop diameters.
List<List<int>> groupColonies(
  List<Colony> colonies,
  double mmPerPx,
  double diameterMm,
) {
  final link = 0.35 * diameterMm / mmPerPx;
  final n = colonies.length;
  final parent = List<int>.generate(n, (i) => i);
  int find(int i) {
    while (parent[i] != i) {
      parent[i] = parent[parent[i]];
      i = parent[i];
    }
    return i;
  }

  for (var i = 0; i < n; i++) {
    final a = colonies[i];
    for (var j = i + 1; j < n; j++) {
      final b = colonies[j];
      final gap = _hypot(a.x - b.x, a.y - b.y) - a.radiusPx - b.radiusPx;
      if (gap <= link) parent[find(i)] = find(j);
    }
  }
  final groups = <int, List<int>>{};
  for (var i = 0; i < n; i++) {
    (groups[find(i)] ??= []).add(i);
  }
  return groups.values.toList();
}

/// A binary image with its 8-connected components.
class _Blobs {
  _Blobs(this.binary, this.width, this.height) {
    labels = Int32List(width * height);
    final stack = <int>[];
    for (var start = 0; start < binary.length; start++) {
      if (binary[start] == 0 || labels[start] != 0) continue;
      final label = area.length + 1;
      var a = 0;
      var sx = 0.0, sy = 0.0;
      labels[start] = label;
      stack.add(start);
      while (stack.isNotEmpty) {
        final i = stack.removeLast();
        final x = i % width, y = i ~/ width;
        a++;
        sx += x;
        sy += y;
        for (var dy = -1; dy <= 1; dy++) {
          final yy = y + dy;
          if (yy < 0 || yy >= height) continue;
          for (var dx = -1; dx <= 1; dx++) {
            final xx = x + dx;
            if (xx < 0 || xx >= width) continue;
            final j = yy * width + xx;
            if (binary[j] == 1 && labels[j] == 0) {
              labels[j] = label;
              stack.add(j);
            }
          }
        }
      }
      area.add(a);
      cx.add(sx / a);
      cy.add(sy / a);
    }
  }

  final Uint8List binary;
  final int width;
  final int height;
  late final Int32List labels;

  /// Per component (label − 1).
  final List<int> area = [];
  final List<double> cx = [];
  final List<double> cy = [];

  /// Fraction of the disc (x, y, r) that is foreground.
  double cover(double x, double y, double r) {
    final x0 = math.max(0, (x - r).truncate());
    final x1 = math.min(width, (x + r).truncate() + 1);
    final y0 = math.max(0, (y - r).truncate());
    final y1 = math.min(height, (y + r).truncate() + 1);
    var n = 0, on = 0;
    for (var yy = y0; yy < y1; yy++) {
      for (var xx = x0; xx < x1; xx++) {
        if (_hypot(xx - x, yy - y) <= r) {
          n++;
          on += binary[yy * width + xx];
        }
      }
    }
    return n == 0 ? 0 : on / n;
  }

  /// Median pixel area of blobs that hold exactly one single colony.
  double? singleColonyArea(List<Colony> colonies, {int minN = 5}) {
    final per = <int, List<Colony>>{};
    for (final c in colonies) {
      final x = math.min(width - 1, c.x.round()),
          y = math.min(height - 1, c.y.round());
      final k = labels[y * width + x];
      if (k > 0) (per[k] ??= []).add(c);
    }
    final areas = <double>[
      for (final e in per.entries)
        if (e.value.length == 1 && e.value.first.n == 1)
          area[e.key - 1].toDouble(),
    ];
    return areas.length >= minN ? median(areas) : null;
  }
}

/// Colony groups and confluent lawns, each as a circle about one drop across.
List<DropCandidate> _candidates(
  List<Colony> colonies,
  _Blobs blobs,
  double mmPerPx,
  double diameterMm,
) {
  final rDrop = diameterMm / 2 / mmPerPx;
  var out = <DropCandidate>[];
  for (final g in groupColonies(colonies, mmPerPx, diameterMm)) {
    var w = 0, sx = 0.0, sy = 0.0;
    for (final i in g) {
      final c = colonies[i];
      w += c.n;
      sx += c.x * c.n;
      sy += c.y * c.n;
    }
    out.add(DropCandidate(sx / w, sy / w, rDrop, w));
  }
  // Confluent lawns: foreground filling most of a drop-sized disc.
  final disc = math.pi * rDrop * rDrop;
  for (var k = 0; k < blobs.area.length; k++) {
    final a = blobs.area[k];
    if (a < kConfluentCover * disc * 0.8 || a > disc * 2.5) continue;
    final cx = blobs.cx[k], cy = blobs.cy[k];
    if (blobs.cover(cx, cy, rDrop) >= kConfluentCover) {
      out = [
        for (final c in out)
          if (_hypot(c.x - cx, c.y - cy) > rDrop) c,
      ];
      out.add(DropCandidate(cx, cy, rDrop, 0, confluent: true));
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Layout fit

typedef _Pt = (double, double);

typedef _Placement = ({List<_Pt> t, LayoutFit fit, double score});

/// Places the template on the candidates: the rotation, translation and scale
/// that put the most candidates on planned positions, inside the plate and
/// near its centre. Returns every distinct refined placement scoring within
/// [keep] of the best, best first: a layout shifted by one row can match
/// nearly as many drops, and the caller chooses by the dilution series.
List<_Placement> _fitLayout(
  List<DropCandidate> cands,
  DropTemplate template,
  List<int> dilutions,
  Plate plate,
  double diameterMm, {
  double keep = 1.0,
}) {
  final mm = plate.mmPerPx;
  final p = [
    for (final q in templatePositionsMm(template, dilutions))
      (q.x / mm, q.y / mm),
  ];
  final c = [for (final k in cands) (k.x, k.y)];
  final wts = [
    for (final k in cands) k.confluent ? 1.0 : math.min(1.0, 0.3 + 0.25 * k.n),
  ];
  final tol = 0.5 * diameterMm / mm;
  final centre = (plate.cx, plate.cy);
  final rOk = plate.radius * 0.92;

  // Symmetry: a ring repeats every 360/n; a grid every 180° (90° when square).
  final double span;
  final List<int> anchors;
  switch (template) {
    case SectorTemplate():
      span = 360 / template.n;
      anchors = const [0];
    case GridTemplate():
      span = template.rows == template.cols ? 90 : 180;
      anchors = List.generate(p.length, (i) => i);
    case FreeTemplate():
      return const [];
  }

  double score(List<_Pt> t) {
    var s = 0.0;
    var mx = 0.0, my = 0.0;
    for (final q in t) {
      if (_hypot(q.$1 - centre.$1, q.$2 - centre.$2) > rOk) s -= 2.0;
      mx += q.$1;
      my += q.$2;
    }
    mx /= t.length;
    my /= t.length;
    final off = _hypot(mx - centre.$1, my - centre.$2) / (0.25 * plate.radius);
    s -= 0.3 * off * off;
    for (var j = 0; j < c.length; j++) {
      var near = double.infinity;
      for (final q in t) {
        final d = _hypot(q.$1 - c[j].$1, q.$2 - c[j].$2);
        if (d < near) near = d;
      }
      if (near < tol) s += wts[j];
      s -= 0.2 * math.min(near, tol) / tol * wts[j];
    }
    return s;
  }

  List<_Pt> rotate(List<_Pt> pts, double deg) {
    final r = deg * math.pi / 180, co = math.cos(r), si = math.sin(r);
    return [
      for (final q in pts) (co * q.$1 - si * q.$2, si * q.$1 + co * q.$2),
    ];
  }

  final hyps = <({double score, double th, _Pt t, int i})>[];
  for (var th = 0.0; th < span; th += 3.0) {
    final rp = rotate(p, th);
    final ts = <_Pt>[
      centre,
      for (var i = 0; i < c.length; i++)
        for (final j in anchors) (c[i].$1 - rp[j].$1, c[i].$2 - rp[j].$2),
    ];
    for (final t in ts) {
      final placed = [for (final q in rp) (q.$1 + t.$1, q.$2 + t.$2)];
      hyps.add((score: score(placed), th: th, t: t, i: hyps.length));
    }
  }
  // Best first; ties keep their order (as Python's stable sort).
  hyps.sort((a, b) {
    final d = b.score.compareTo(a.score);
    return d != 0 ? d : a.i.compareTo(b.i);
  });
  final top = hyps.first.score;

  final out = <_Placement>[];
  for (final h in hyps) {
    if (h.score < top - keep - 1.0 || out.length >= 8) break;
    var deg = h.th, scale = 1.0;
    var t = [for (final q in rotate(p, deg)) (q.$1 + h.t.$1, q.$2 + h.t.$2)];
    // Refine: similarity transform (Procrustes) on matched pairs, twice.
    for (var it = 0; it < 2; it++) {
      final pairs = _match(t, c, tol);
      if (pairs.length < 2) break;
      final f = _procrustes(
        [for (final pr in pairs) p[pr.$1]],
        [for (final pr in pairs) c[pr.$2]],
      );
      if (!(f.s > 0.8 && f.s < 1.25)) break;
      t = [
        for (final q in rotate(p, f.deg))
          (q.$1 * f.s + f.tx, q.$2 * f.s + f.ty),
      ];
      scale = f.s;
      deg = f.deg;
    }
    final sc = score(t);
    final same = out.any((o) {
      var m = 0.0;
      for (var k = 0; k < t.length; k++) {
        m = math.max(m, (t[k].$1 - o.t[k].$1).abs());
        m = math.max(m, (t[k].$2 - o.t[k].$2).abs());
      }
      return m < tol;
    });
    if (same) continue;
    final pairs = _match(t, c, tol);
    var mx = 0.0, my = 0.0;
    for (final q in t) {
      mx += q.$1;
      my += q.$2;
    }
    var rDeg = deg % 360;
    if (rDeg > 180) rDeg -= 360;
    out.add((
      t: t,
      fit: LayoutFit(
        rDeg,
        scale,
        mx / t.length,
        my / t.length,
        pairs.length,
        c.length - pairs.length,
      ),
      score: sc,
    ));
  }
  // Stable: Dart's sort is not, so tie-break on the order found.
  final idx = List.generate(out.length, (i) => i)
    ..sort((a, b) {
      final d = out[b].score.compareTo(out[a].score);
      return d != 0 ? d : a.compareTo(b);
    });
  final sorted = [for (final i in idx) out[i]];
  final best = sorted.first.score;
  return [
    for (final o in sorted)
      if (o.score >= best - keep) o,
  ];
}

/// Greedy one-to-one pairs (position, candidate) closer than [tol].
List<(int, int)> _match(List<_Pt> t, List<_Pt> c, double tol) {
  if (c.isEmpty) return const [];
  final all = <(double, int, int)>[];
  for (var p = 0; p < t.length; p++) {
    for (var k = 0; k < c.length; k++) {
      final d = _hypot(t[p].$1 - c[k].$1, t[p].$2 - c[k].$2);
      if (d < tol) all.add((d, p, k));
    }
  }
  all.sort((a, b) {
    final d = a.$1.compareTo(b.$1);
    if (d != 0) return d;
    final e = a.$2.compareTo(b.$2);
    return e != 0 ? e : a.$3.compareTo(b.$3);
  });
  final usedP = <int>{}, usedC = <int>{};
  final pairs = <(int, int)>[];
  for (final (_, p, k) in all) {
    if (usedP.contains(p) || usedC.contains(k)) continue;
    pairs.add((p, k));
    usedP.add(p);
    usedC.add(k);
  }
  return pairs;
}

/// Scale, rotation and translation with dst ≈ s·R·src + t (least squares; in
/// two dimensions the rotation has a closed form).
({double s, double deg, double tx, double ty}) _procrustes(
  List<_Pt> src,
  List<_Pt> dst,
) {
  final n = src.length;
  var msx = 0.0, msy = 0.0, mdx = 0.0, mdy = 0.0;
  for (var i = 0; i < n; i++) {
    msx += src[i].$1 / n;
    msy += src[i].$2 / n;
    mdx += dst[i].$1 / n;
    mdy += dst[i].$2 / n;
  }
  var dot = 0.0, cross = 0.0, norm = 0.0;
  for (var i = 0; i < n; i++) {
    final ax = src[i].$1 - msx, ay = src[i].$2 - msy;
    final bx = dst[i].$1 - mdx, by = dst[i].$2 - mdy;
    dot += ax * bx + ay * by;
    cross += ax * by - ay * bx;
    norm += ax * ax + ay * ay;
  }
  final th = math.atan2(cross, dot);
  final s = math.sqrt(dot * dot + cross * cross) / math.max(norm, 1e-9);
  final co = math.cos(th), si = math.sin(th);
  return (
    s: s,
    deg: th * 180 / math.pi,
    tx: mdx - s * (co * msx - si * msy),
    ty: mdy - s * (si * msx + co * msy),
  );
}

// ---------------------------------------------------------------------------
// Labels

/// Ways the planned positions can be relabelled without moving them: a ring
/// can start at any drop and run either way; a grid can be the other way up
/// (and a square grid a quarter turn round).
List<List<int>> _orientations(DropTemplate template) {
  switch (template) {
    case SectorTemplate(:final n):
      return [
        for (var s = 0; s < n; s++) [for (var k = 0; k < n; k++) (s + k) % n],
        for (var s = 0; s < n; s++)
          [for (var k = 0; k < n; k++) ((s - k) % n + n) % n],
      ];
    case GridTemplate(:final rows, :final cols):
      int idx(int r, int c) => r * cols + c;
      List<int> all(int Function(int r, int c) f) => [
        for (var r = 0; r < rows; r++)
          for (var c = 0; c < cols; c++) f(r, c),
      ];
      return [
        all((r, c) => idx(r, c)),
        all((r, c) => idx(rows - 1 - r, c)),
        all((r, c) => idx(r, cols - 1 - c)),
        all((r, c) => idx(rows - 1 - r, cols - 1 - c)),
        if (rows == cols) ...[
          all((r, c) => idx(c, r)),
          all((r, c) => idx(cols - 1 - c, r)),
          all((r, c) => idx(c, rows - 1 - r)),
          all((r, c) => idx(cols - 1 - c, rows - 1 - r)),
        ],
      ];
    case FreeTemplate():
      return const [];
  }
}

/// Poisson log-likelihood of the counts for one density (its best value),
/// with confluent drops taken as [cap] colonies.
double _dilutionLogLik(
  List<int> counts,
  List<int> dils,
  double volumeMl,
  List<bool> confluent, {
  int cap = 200,
}) {
  final x = [
    for (var i = 0; i < counts.length; i++)
      (confluent[i] ? cap : counts[i]).toDouble(),
  ];
  final v = [for (final d in dils) volumeMl * math.pow(10.0, -d)];
  final sx = x.fold(0.0, (s, e) => s + e);
  final sv = v.fold(0.0, (s, e) => s + e);
  final lam = sx > 0 ? sx / sv : 0.0;
  var ll = 0.0;
  for (var i = 0; i < x.length; i++) {
    final mu = math.max(lam * v[i], 1e-12);
    ll += x[i] * math.log(mu) - mu;
  }
  return ll;
}

// ---------------------------------------------------------------------------
// Whole plate

/// Finds, labels and counts the drops of a drop plate on [gray] (results in
/// the same pixels).
DropPlateResult countDropPlate(
  GrayImage gray,
  DropTemplate template,
  List<int> dilutions, {
  double volumeUl = 10,
  Plate? plate,
  PlateFormat format = PlateFormat.dish90,
  double? diameterMm,
}) {
  plate ??= findPlate(gray, format: format);
  final mm = plate.mmPerPx;
  final diam = diameterMm ?? dropDiameterMm(volumeUl);
  final w = gray.width, h = gray.height;
  final mask = plate.mask(w, h, rimFraction: 0.95);
  // A wide background window, so a confluent drop is not absorbed into it.
  final bg = estimateBackground(gray, plate, kernelMm: 15);
  final (fg, _) = foreground(gray, bg, mask);
  final det = detect(fg, mask, mm, const DetectParams(minDiameterMm: 0.2));
  final binary = Uint8List(w * h);
  for (var i = 0; i < binary.length; i++) {
    if (mask[i] == 1 && fg.data[i] > det.threshold) binary[i] = 1;
  }
  final blobs = _Blobs(binary, w, h);
  final colonies = det.colonies;
  final cands = _candidates(colonies, blobs, mm, diam);
  final rDrop = diam / 2 / mm;
  final flags = <String>[];

  // Colonies to their nearest drop (within 1.1 drop radii); the rest are strays.
  ({List<int> owner, List<bool> conf, List<int> counts}) assign(List<_Pt> t) {
    final owner = List<int>.filled(colonies.length, -1);
    if (t.isNotEmpty) {
      for (var i = 0; i < colonies.length; i++) {
        final col = colonies[i];
        var best = 0, bd = double.infinity;
        for (var k = 0; k < t.length; k++) {
          final d = _hypot(t[k].$1 - col.x, t[k].$2 - col.y);
          if (d < bd) {
            bd = d;
            best = k;
          }
        }
        if (bd <= rDrop * kAssignRadius) owner[i] = best;
      }
    }
    final conf = [
      for (final q in t)
        cands.any((k) => k.confluent && _hypot(k.x - q.$1, k.y - q.$2) < rDrop),
    ];
    final counts = List<int>.filled(t.length, 0);
    for (var i = 0; i < colonies.length; i++) {
      if (owner[i] >= 0) counts[owner[i]] += colonies[i].n;
    }
    return (owner: owner, conf: conf, counts: counts);
  }

  final List<_Pt> t;
  final List<PlannedDrop> plan;
  final LayoutFit? fit;
  final List<int> order;
  final List<int> owner;
  final List<bool> conf;
  final List<int> counts;
  if (template is FreeTemplate) {
    cands.sort((a, b) {
      final d = (a.y / (2 * rDrop)).round().compareTo(
        (b.y / (2 * rDrop)).round(),
      );
      return d != 0 ? d : a.x.compareTo(b.x);
    });
    t = [for (final k in cands) (k.x, k.y)];
    plan = [
      for (var k = 0; k < t.length; k++)
        (
          x: 0.0,
          y: 0.0,
          dilutionExp: dilutions[math.min(k, dilutions.length - 1)],
          replicate: 1,
        ),
    ];
    fit = null;
    (:owner, :conf, :counts) = assign(t);
    order = List.generate(t.length, (i) => i);
  } else {
    plan = templatePositionsMm(template, dilutions);
    // Among placements that fit about equally well, the one (and the way
    // round) whose counts best follow the dilution series.
    ({
      double ll,
      _Placement pl,
      List<int> owner,
      List<bool> conf,
      List<int> counts,
      List<int> o,
    })?
    best;
    final orients = _orientations(template);
    for (final pl in _fitLayout(cands, template, dilutions, plate, diam)) {
      final a = assign(pl.t);
      for (final o in orients) {
        final ll = _dilutionLogLik(
          [for (final k in o) a.counts[k]],
          [for (var s = 0; s < o.length; s++) plan[s].dilutionExp],
          volumeUl / 1000,
          [for (final k in o) a.conf[k]],
        );
        if (best == null || ll > best.ll + 1e-9) {
          best = (
            ll: ll,
            pl: pl,
            owner: a.owner,
            conf: a.conf,
            counts: a.counts,
            o: o,
          );
        }
      }
    }
    t = best!.pl.t;
    fit = best.pl.fit;
    owner = best.owner;
    conf = best.conf;
    counts = best.counts;
    order = best.o;
    if (fit.outside > 0) flags.add('colonies_outside_drops');
    final strong = cands.where((k) => k.n >= 3 || k.confluent).length;
    if (fit.matched < math.max(1, strong ~/ 2)) flags.add('layout_uncertain');
  }

  // Merged colonies in a crowded drop are undercounted by the detector: also
  // count them by area (colony pixels ÷ the pixels of a typical isolated
  // colony) and keep the larger.
  final unit = blobs.singleColonyArea(colonies);
  final disc = math.pi * rDrop * rDrop;
  final drops = <FoundDrop>[];
  for (var slot = 0; slot < order.length; slot++) {
    final k = order[slot];
    final (x, y) = t[k];
    final members = [
      for (var i = 0; i < colonies.length; i++)
        if (owner[i] == k) i,
    ];
    final cover = blobs.cover(x, y, rDrop);
    final crowded =
        !conf[k] &&
        (cover > kCrowdedCover || members.any((i) => colonies[i].n >= 3));
    var count = counts[k];
    if (crowded && unit != null && unit > 0) {
      count = math.max(count, (cover * disc / unit).round());
    }
    drops.add(
      FoundDrop(
        x: x,
        y: y,
        radiusPx: rDrop,
        position: fit != null ? slot : null,
        dilutionExp: plan[slot].dilutionExp,
        replicate: plan[slot].replicate,
        count: count,
        confluent: conf[k],
        crowded: crowded,
        colonies: members,
      ),
    );
  }
  // Which drop of a dilution is "replicate 1" cannot be seen on the plate:
  // number them in reading order (rows of one drop diameter, then left to
  // right).
  int readingOrder(FoundDrop a, FoundDrop b) {
    final d = (a.y / (2 * rDrop)).round().compareTo(
      (b.y / (2 * rDrop)).round(),
    );
    return d != 0 ? d : a.x.compareTo(b.x);
  }

  for (final dil in {for (final d in drops) d.dilutionExp}) {
    final same = drops.where((d) => d.dilutionExp == dil).toList()
      ..sort(readingOrder);
    for (var i = 0; i < same.length; i++) {
      same[i].replicate = i + 1;
    }
  }
  drops.sort((a, b) {
    var d = (a.position ?? 0).compareTo(b.position ?? 0);
    if (d != 0) return d;
    d = a.y.compareTo(b.y);
    return d != 0 ? d : a.x.compareTo(b.x);
  });
  return DropPlateResult(
    plate: plate,
    drops: drops,
    colonies: colonies,
    strays: [
      for (var i = 0; i < colonies.length; i++)
        if (owner[i] < 0) i,
    ],
    fit: fit,
    flags: flags,
    imageWidth: w,
    imageHeight: h,
  );
}

/// A drop-plate photo to count: bytes, template, dilutions, drop volume (µL),
/// dish format, and the plate circle in the photo's pixels when the user has
/// set it (else it is searched for). A record so it can run in a background
/// isolate.
typedef DropJob = (
  Uint8List,
  DropTemplate,
  List<int>,
  double,
  PlateFormat,
  Plate?,
);

/// Decodes a photo, applies its EXIF rotation, counts a downscaled copy and
/// returns the drops in the photo's full-resolution pixels, with each
/// colony's colour.
DropPlateResult countDropPlateInPhoto(DropJob job) {
  final (bytes, template, dilutions, volumeUl, format, plate) = job;
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('Unsupported image');
  final photo = img.bakeOrientation(decoded);
  final short = math.min(photo.width, photo.height);
  final scale = math.min(1.0, kWorkShortSide / short);
  final work = scale < 1
      ? img.copyResize(
          photo,
          width: (photo.width * scale).round(),
          height: (photo.height * scale).round(),
          interpolation: img.Interpolation.average,
        )
      : photo;
  final res = countDropPlate(
    grayFromImage(work),
    template,
    dilutions,
    volumeUl: volumeUl,
    format: format,
    plate: plate?.scaled(scale),
  );
  final full = scale < 1 ? res.scaled(1 / scale) : res;
  final colours = colonyColours(photo, full.colonies);
  return full._copy(
    colonies: [
      for (var i = 0; i < full.colonies.length; i++)
        full.colonies[i].withColour(colours[i]),
    ],
    imageWidth: photo.width,
    imageHeight: photo.height,
  );
}

double _hypot(double x, double y) => math.sqrt(x * x + y * y);
