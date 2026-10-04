import 'dart:math' as math;

import 'classical.dart';

/// One drop on a drop plate (Miles–Misra), in photo pixels.
class Spot {
  const Spot(
    this.cx,
    this.cy,
    this.radius, {
    this.dilutionExp = 0,
    this.replicate = 1,
    this.tntc = false,
  });

  final double cx;
  final double cy;
  final double radius;

  /// Dilution of this drop as a power of ten (4 → 10⁻⁴).
  final int dilutionExp;
  final int replicate;

  /// Confluent / too many to count; excluded unless no other drop is usable.
  final bool tntc;

  bool contains(double x, double y) =>
      (x - cx) * (x - cx) + (y - cy) * (y - cy) <= radius * radius;

  Spot copyWith({
    double? cx,
    double? cy,
    double? radius,
    int? dilutionExp,
    int? replicate,
    bool? tntc,
  }) => Spot(
    cx ?? this.cx,
    cy ?? this.cy,
    radius ?? this.radius,
    dilutionExp: dilutionExp ?? this.dilutionExp,
    replicate: replicate ?? this.replicate,
    tntc: tntc ?? this.tntc,
  );

  Map<String, dynamic> toJson() => {
    'cx': cx,
    'cy': cy,
    'r': radius,
    'd': dilutionExp,
    'rep': replicate,
    if (tntc) 'tntc': true,
  };

  factory Spot.fromJson(Map<String, dynamic> j) => Spot(
    (j['cx'] as num).toDouble(),
    (j['cy'] as num).toDouble(),
    (j['r'] as num).toDouble(),
    dilutionExp: (j['d'] as num?)?.toInt() ?? 0,
    replicate: (j['rep'] as num?)?.toInt() ?? 1,
    tntc: j['tntc'] as bool? ?? false,
  );
}

/// Colonies counted inside [spot] (clusters count as their estimated size).
int countInSpot(Spot spot, List<Colony> colonies) =>
    colonies.where((c) => spot.contains(c.x, c.y)).fold(0, (s, c) => s + c.n);

/// Suggests drop positions by grouping colonies that lie close together.
///
/// Colonies closer than [linkMm] join the same group (single linkage); each
/// group becomes a circle around its colonies, at least [dropDiameterMm] wide.
/// Overlapping circles are merged. Spots come back in reading order (rows top
/// to bottom, left to right). Confluent drops are not detected as colonies, so
/// they need adding by hand.
List<Spot> suggestSpots(
  List<Colony> colonies,
  double mmPerPx, {
  double dropDiameterMm = 7,
  double linkMm = 2.5,
}) {
  if (colonies.isEmpty) return [];
  final link = linkMm / mmPerPx;
  final minR = dropDiameterMm / 2 / mmPerPx;

  // Union-find over colony pairs closer than `link`.
  final parent = List<int>.generate(colonies.length, (i) => i);
  int find(int i) {
    while (parent[i] != i) {
      parent[i] = parent[parent[i]];
      i = parent[i];
    }
    return i;
  }

  for (var i = 0; i < colonies.length; i++) {
    for (var j = i + 1; j < colonies.length; j++) {
      final a = colonies[i], b = colonies[j];
      final gap =
          math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2)) -
          a.radiusPx -
          b.radiusPx;
      if (gap <= link) parent[find(i)] = find(j);
    }
  }
  final groups = <int, List<Colony>>{};
  for (var i = 0; i < colonies.length; i++) {
    (groups[find(i)] ??= []).add(colonies[i]);
  }

  var circles = [for (final g in groups.values) _enclose(g, minR)];
  // Merge circles that overlap (one drop split into several groups).
  var merged = true;
  while (merged) {
    merged = false;
    outer:
    for (var i = 0; i < circles.length; i++) {
      for (var j = i + 1; j < circles.length; j++) {
        final a = circles[i], b = circles[j];
        final d = math.sqrt(
          math.pow(a.cx - b.cx, 2) + math.pow(a.cy - b.cy, 2),
        );
        if (d < (a.radius + b.radius) * 0.8) {
          final members = colonies
              .where((c) => a.contains(c.x, c.y) || b.contains(c.x, c.y))
              .toList();
          circles[i] = _enclose(
            members.isEmpty ? [] : members,
            minR,
            fallback: a,
          );
          circles.removeAt(j);
          merged = true;
          break outer;
        }
      }
    }
  }
  return sortReadingOrder(circles);
}

/// Rows top to bottom (spots within a row band share a row), then left to right.
List<Spot> sortReadingOrder(List<Spot> spots) {
  if (spots.isEmpty) return spots;
  final rowBand = spots.map((s) => s.radius).reduce(math.max);
  final byY = List.of(spots)..sort((a, b) => a.cy.compareTo(b.cy));
  final rows = <List<Spot>>[];
  for (final s in byY) {
    if (rows.isNotEmpty && (s.cy - rows.last.first.cy).abs() < rowBand) {
      rows.last.add(s);
    } else {
      rows.add([s]);
    }
  }
  return [
    for (final row in rows) ...(row..sort((a, b) => a.cx.compareTo(b.cx))),
  ];
}

Spot _enclose(List<Colony> g, double minR, {Spot? fallback}) {
  if (g.isEmpty) return fallback!;
  final cx = g.fold(0.0, (s, c) => s + c.x) / g.length;
  final cy = g.fold(0.0, (s, c) => s + c.y) / g.length;
  var r = minR;
  for (final c in g) {
    r = math.max(
      r,
      math.sqrt(math.pow(c.x - cx, 2) + math.pow(c.y - cy, 2)) +
          c.radiusPx * 1.2,
    );
  }
  return Spot(cx, cy, r);
}
