import 'dart:math' as math;

import 'classical.dart';
import 'plate.dart';

/// One photo of a time-lapse series.
class TimelapseFrame {
  const TimelapseFrame(this.hours, this.plate, this.colonies);

  /// Hours since plating (or since the first photo).
  final double hours;
  final Plate plate;
  final List<Colony> colonies;

  /// Colony centres and diameters in mm, relative to the plate centre and
  /// with the plate's own rotation removed.
  List<(double, double, double)> get pointsMm {
    final s = plate.mmPerPx;
    final c = math.cos(-plate.angle), sn = math.sin(-plate.angle);
    return [
      for (final col in colonies)
        if (col.n == 1)
          (
            ((col.x - plate.cx) * c - (col.y - plate.cy) * sn) * s,
            ((col.x - plate.cx) * sn + (col.y - plate.cy) * c) * s,
            2 * col.radiusPx * s,
          ),
    ];
  }

  /// Image pixel position of plate coordinates (mm) from [pointsMm].
  (double, double) toImage(double xMm, double yMm) {
    final s = plate.mmPerPx;
    final c = math.cos(plate.angle), sn = math.sin(plate.angle);
    return (
      plate.cx + (xMm * c - yMm * sn) / s,
      plate.cy + (xMm * sn + yMm * c) / s,
    );
  }
}

/// Rotation (and mirroring) that maps one photo's plate coordinates onto the
/// next one's, found by matching colonies.
class Alignment {
  const Alignment(this.angle, this.mirrored, this.dx, this.dy, this.matched);

  static const identity = Alignment(0, false, 0, 0, 0);

  final double angle;
  final bool mirrored;
  final double dx, dy;

  /// Colonies of the earlier photo that found a partner.
  final int matched;

  (double, double) apply(double x, double y) {
    final xm = mirrored ? -x : x;
    final c = math.cos(angle), s = math.sin(angle);
    return (xm * c - y * s + dx, xm * s + y * c + dy);
  }
}

/// A colony followed through the series, in the last photo's coordinates.
class ColonyTrack {
  ColonyTrack(this.x, this.y, this.sizes);

  final double x, y;

  /// (hours, diameter in mm) for each photo the colony is seen in.
  final List<(double, double)> sizes;

  /// First photo the colony is seen in.
  double get appearedH => sizes.first.$1;

  /// Diameter growth in mm per hour (least squares), when seen in ≥ 2 photos.
  double? get growthMmPerH {
    if (sizes.length < 2) return null;
    final n = sizes.length;
    final mt = sizes.fold(0.0, (s, e) => s + e.$1) / n;
    final md = sizes.fold(0.0, (s, e) => s + e.$2) / n;
    var num = 0.0, den = 0.0;
    for (final (t, d) in sizes) {
      num += (t - mt) * (d - md);
      den += (t - mt) * (t - mt);
    }
    return den == 0 ? null : num / den;
  }
}

class TimelapseResult {
  TimelapseResult(this.frames, this.alignments, this.tracks);

  /// Sorted by time.
  final List<TimelapseFrame> frames;

  /// [alignments][i] maps frame i onto frame i + 1.
  final List<Alignment> alignments;
  final List<ColonyTrack> tracks;

  /// Colonies first seen in each photo.
  List<int> get newPerFrame => [
    for (final f in frames) tracks.where((t) => t.appearedH == f.hours).length,
  ];

  double? get medianAppearanceH =>
      _median([for (final t in tracks) t.appearedH]);

  double? get medianGrowthMmPerH => _median([
    for (final t in tracks)
      if (t.growthMmPerH != null) t.growthMmPerH!,
  ]);
}

double? _median(List<double> v) {
  if (v.isEmpty) return null;
  v.sort();
  final n = v.length;
  return n.isOdd ? v[n ~/ 2] : (v[n ~/ 2 - 1] + v[n ~/ 2]) / 2;
}

int _matches(
  List<(double, double, double)> a,
  List<(double, double, double)> b,
  Alignment t,
  double tolMm,
) {
  var m = 0;
  final tol2 = tolMm * tolMm;
  for (final p in a) {
    final (x, y) = t.apply(p.$1, p.$2);
    for (final q in b) {
      final dx = q.$1 - x, dy = q.$2 - y;
      if (dx * dx + dy * dy <= tol2) {
        m++;
        break;
      }
    }
  }
  return m;
}

/// Best rotation / mirror / small shift taking colonies [a] (earlier photo)
/// onto [b] (later photo). Colonies only appear and grow, so most of [a]
/// should have a partner in [b]. With fewer than 3 colonies the photos are
/// assumed to have the same orientation.
Alignment alignColonies(
  List<(double, double, double)> a,
  List<(double, double, double)> b, {
  double tolMm = 1.0,
}) {
  if (a.length < 3 || b.isEmpty) {
    return Alignment(0, false, 0, 0, _matches(a, b, Alignment.identity, tolMm));
  }
  var best = Alignment.identity;
  var bestM = -1;
  void tryAt(double angle, bool mirrored, double dx, double dy) {
    final t = Alignment(angle, mirrored, dx, dy, 0);
    final m = _matches(a, b, t, tolMm);
    // Ties prefer no rotation and no mirroring.
    if (m > bestM ||
        (m == bestM &&
            (angle.abs() + (mirrored ? 10 : 0)) <
                (best.angle.abs() + (best.mirrored ? 10 : 0)))) {
      bestM = m;
      best = Alignment(angle, mirrored, dx, dy, m);
    }
  }

  const deg = math.pi / 180;
  for (final mirrored in const [false, true]) {
    for (var k = -179; k <= 180; k += 2) {
      tryAt(k * deg, mirrored, 0, 0);
    }
  }
  final coarse = best;
  for (var k = -2.0; k <= 2.0; k += 0.25) {
    tryAt(coarse.angle + k * deg, coarse.mirrored, 0, 0);
  }
  // Refine the shift from the matched pairs (plate centre errors).
  for (var iter = 0; iter < 2; iter++) {
    var sx = 0.0, sy = 0.0, n = 0;
    for (final p in a) {
      final (x, y) = best.apply(p.$1, p.$2);
      (double, double, double)? q;
      var bd = tolMm * tolMm;
      for (final c in b) {
        final d = (c.$1 - x) * (c.$1 - x) + (c.$2 - y) * (c.$2 - y);
        if (d <= bd) {
          bd = d;
          q = c;
        }
      }
      if (q != null) {
        sx += q.$1 - x;
        sy += q.$2 - y;
        n++;
      }
    }
    if (n == 0) break;
    tryAt(best.angle, best.mirrored, best.dx + sx / n, best.dy + sy / n);
  }
  return best;
}

/// Follows colonies through photos of one plate: aligns each photo to the
/// next, then traces every colony of the last photo back to the first photo
/// it appears in.
TimelapseResult analyseTimelapse(
  List<TimelapseFrame> frames, {
  double tolMm = 1.0,
}) {
  final f = [...frames]..sort((a, b) => a.hours.compareTo(b.hours));
  if (f.isEmpty) return TimelapseResult(f, const [], const []);
  final pts = [for (final x in f) x.pointsMm];
  final align = [
    for (var i = 0; i + 1 < f.length; i++)
      alignColonies(pts[i], pts[i + 1], tolMm: tolMm),
  ];
  // Every frame's points in the last frame's coordinates.
  final inLast = <List<(double, double, double)>>[];
  for (var i = 0; i < f.length; i++) {
    inLast.add([
      for (final p in pts[i])
        () {
          var (x, y) = (p.$1, p.$2);
          for (var k = i; k < align.length; k++) {
            (x, y) = align[k].apply(x, y);
          }
          return (x, y, p.$3);
        }(),
    ]);
  }
  final tracks = <ColonyTrack>[];
  for (final c in inLast.last) {
    final sizes = <(double, double)>[];
    for (var i = 0; i < f.length; i++) {
      (double, double, double)? best;
      var bd = tolMm * tolMm;
      for (final q in inLast[i]) {
        final d = (q.$1 - c.$1) * (q.$1 - c.$1) + (q.$2 - c.$2) * (q.$2 - c.$2);
        if (d <= bd) {
          bd = d;
          best = q;
        }
      }
      if (best != null) sizes.add((f[i].hours, best.$3));
    }
    tracks.add(ColonyTrack(c.$1, c.$2, sizes));
  }
  return TimelapseResult(f, align, tracks);
}
