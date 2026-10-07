import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'gray_image.dart';
import 'pipeline.dart' show grayFromImage, kWorkShortSide;
import 'plate.dart';

// Inhibition zone measurement (mirrors ml/colonycounter/zones.py; keep the two
// in step, the fixtures in test/fixtures/zones_*.json check agreement).
//
// photo → plate → disks / wells (signed ring score, coarse then full
// resolution, circle fitted to the disk edge) → scale from the 6 mm disks →
// 180 rays per disk: edge half-way from clear agar to lawn, held for 1.5 mm →
// circle fit → diameter, confidence, flags. Measurement only: no S/I/R.

enum ZoneAssay { disk, well }

const int kZoneRays = 180;

/// Below this fraction of rays agreeing, the zone is left to the user.
const double kMinAgreeing = 0.15;

/// Disk radius (px) in the downscaled copy used to find candidates. Wells need
/// more detail: their cut edge is a thin line that vanishes when scaled down.
const Map<ZoneAssay, double> kCoarseRadiusPx = {
  ZoneAssay.disk: 12,
  ZoneAssay.well: 20,
};
const int kMaxDiskCandidates = 40;
const List<double> kDiskSizeFactors = [0.8, 1.0, 1.25];

/// Grey levels. Synthetic plates: real disks/wells ≥ 10, lawn and zone edges
/// ≤ 6.2. To be re-checked on real photos.
const double kMinDiskScore = 8;
const double kRidgeGapPx = 2;
const int kRingSectors = 8;

class ZoneParams {
  const ZoneParams({
    this.edgeLevel = 0.5,
    this.persistMm = 1.5,
    this.startGapMm = 0.4,
    this.minContrast = 10,
    this.maxZoneMm = 50,
    this.hazyWidthMm = 1.0,
    this.scaleTolerance = 0.05,
  });

  /// Fraction of the zone→lawn contrast where the edge is read.
  final double edgeLevel;

  /// Growth must hold this long to count as the edge (skips colonies in zones).
  final double persistMm;

  /// Rays start this far outside the disk edge.
  final double startGapMm;

  /// Grey levels between zone and lawn for a zone to count.
  final double minContrast;
  final double maxZoneMm;

  /// 20→80 % edge width above this is "hazy".
  final double hazyWidthMm;
  final double scaleTolerance;
}

/// A paper disk or agar well, in image pixels.
class Disk {
  const Disk(
    this.x,
    this.y,
    this.radiusPx, {
    this.score = 0,
    this.measured = true,
  });

  final double x;
  final double y;
  final double radiusPx;
  final double score;

  /// Radius fitted to the edge, not assumed from the plate scale.
  final bool measured;

  Disk scaled(double s) =>
      Disk(x * s, y * s, radiusPx * s, score: score, measured: measured);
}

class Zone {
  Zone({
    required this.x,
    required this.y,
    required this.diskRadiusPx,
    required this.radiusPx,
    required this.diameterMm,
    required this.confidence,
    required this.edgeWidthMm,
    List<String>? flags,
  }) : flags = flags ?? [];

  final double x;
  final double y;
  final double diskRadiusPx;

  /// NaN when unmeasured.
  final double radiusPx;

  /// NaN when unmeasured.
  final double diameterMm;
  final double confidence;
  final double edgeWidthMm;
  final List<String> flags;

  bool get measured => diameterMm.isFinite;

  /// Whole mm as shown on screen (EUCAST reads to the nearest mm); null if
  /// unmeasured.
  int? get diameterRounded =>
      diameterMm.isFinite ? (diameterMm + 0.5).floor() : null;

  Zone scaled(double s) => Zone(
    x: x * s,
    y: y * s,
    diskRadiusPx: diskRadiusPx * s,
    radiusPx: radiusPx * s,
    diameterMm: diameterMm,
    confidence: confidence,
    edgeWidthMm: edgeWidthMm,
    flags: List.of(flags),
  );

  Map<String, dynamic> toJson() => {
    'x': x,
    'y': y,
    'disk_r': diskRadiusPx,
    'r': radiusPx.isFinite ? radiusPx : null,
    'mm': diameterMm.isFinite ? diameterMm : null,
    'conf': confidence,
    'edge_mm': edgeWidthMm,
    if (flags.isNotEmpty) 'flags': flags,
  };

  factory Zone.fromJson(Map<String, dynamic> j) => Zone(
    x: (j['x'] as num).toDouble(),
    y: (j['y'] as num).toDouble(),
    diskRadiusPx: (j['disk_r'] as num).toDouble(),
    radiusPx: (j['r'] as num?)?.toDouble() ?? double.nan,
    diameterMm: (j['mm'] as num?)?.toDouble() ?? double.nan,
    confidence: (j['conf'] as num?)?.toDouble() ?? 0,
    edgeWidthMm: (j['edge_mm'] as num?)?.toDouble() ?? 0,
    flags: [for (final f in j['flags'] as List? ?? const []) f as String],
  );
}

class ZoneResult {
  const ZoneResult({
    required this.plate,
    required this.assay,
    required this.zones,
    required this.polarity,
    required this.diskScaleRatio,
    required this.flags,
    required this.imageWidth,
    required this.imageHeight,
  });

  final Plate plate;
  final ZoneAssay assay;
  final List<Zone> zones;

  /// "dark_zone" (reflected light), "bright_zone" (back-lit) or "unknown".
  final String polarity;

  /// Measured disk diameter / nominal at the plate's scale; 1.0 is perfect.
  final double diskScaleRatio;

  /// scale_mismatch, scale_unchecked, no_disks.
  final List<String> flags;
  final int imageWidth;
  final int imageHeight;
}

class ZoneOptions {
  const ZoneOptions({
    this.format = PlateFormat.dish90,
    this.assay = ZoneAssay.disk,
    this.diskMm = 6.0,
    this.plate,
    this.disks,
    this.params = const ZoneParams(),
  });

  final PlateFormat format;
  final ZoneAssay assay;

  /// Disk diameter, or the well diameter for wells.
  final double diskMm;

  /// Skip detection (e.g. after manual fixes); in the image's pixels.
  final Plate? plate;
  final List<Disk>? disks;
  final ZoneParams params;
}

/// Decodes a photo, measures a downscaled copy and returns results in the
/// photo's full-resolution pixels. Takes a record so it can run in `compute`.
ZoneResult measureZonesInPhoto((Uint8List, ZoneOptions) job) {
  final decoded = img.decodeImage(job.$1);
  if (decoded == null) throw const FormatException('Unsupported image');
  final photo = img.bakeOrientation(decoded);
  final o = job.$2;
  final s = math.min(1.0, kWorkShortSide / math.min(photo.width, photo.height));
  final work = s < 1
      ? img.copyResize(
          photo,
          width: (photo.width * s).round(),
          height: (photo.height * s).round(),
          interpolation: img.Interpolation.average,
        )
      : photo;
  final res = measureZones(
    grayFromImage(work),
    ZoneOptions(
      format: o.format,
      assay: o.assay,
      diskMm: o.diskMm,
      plate: o.plate?.scaled(s),
      disks: o.disks?.map((d) => d.scaled(s)).toList(),
      params: o.params,
    ),
  );
  final up = 1 / s;
  return ZoneResult(
    plate: res.plate.scaled(up),
    assay: res.assay,
    zones: [for (final z in res.zones) z.scaled(up)],
    polarity: res.polarity,
    diskScaleRatio: res.diskScaleRatio,
    flags: res.flags,
    imageWidth: photo.width,
    imageHeight: photo.height,
  );
}

/// Measures every zone on a (work-size) grayscale image.
ZoneResult measureZones(GrayImage gray, [ZoneOptions o = const ZoneOptions()]) {
  final plate = o.plate ?? findPlate(gray, format: o.format);
  final disks = o.disks ?? findDisks(gray, plate, o.diskMm, o.assay);
  final flags = <String>[];
  var ratio = 1.0;
  var scalePlate = plate;
  final measured = [
    for (final d in disks)
      if (d.measured) d.radiusPx,
  ];
  if (measured.isNotEmpty) {
    final diskPx = 2 * median(measured);
    ratio = diskPx * plate.mmPerPx / o.diskMm;
    if ((ratio - 1).abs() > o.params.scaleTolerance) {
      flags.add('scale_mismatch');
    } else if (o.assay == ZoneAssay.disk) {
      // Paper disks are made to 6.0 mm, a better ruler than the dish edge
      // (the plate finder tends to lock onto the dish wall, outside the agar).
      scalePlate = Plate(
        plate.cx,
        plate.cy,
        plate.radius,
        diameterMm: o.diskMm / diskPx * 2 * plate.radius,
      );
    }
  } else if (disks.isNotEmpty) {
    flags.add('scale_unchecked');
  } else {
    flags.add('no_disks');
  }
  final (zones, polarity) = _measureAll(
    gray,
    scalePlate,
    disks,
    o.diskMm,
    o.params,
  );
  return ZoneResult(
    plate: plate,
    assay: o.assay,
    zones: zones,
    polarity: polarity,
    diskScaleRatio: ratio,
    flags: flags,
    imageWidth: gray.width,
    imageHeight: gray.height,
  );
}

// ---------------------------------------------------------------------------
// Finding disks and wells

/// Disks and wells: circles of the known size, darker or lighter all round.
///
/// A candidate centre scores the brightness step across a ring (measured along
/// the radius) plus a thin line on the ring (a well's cut edge). The ring is
/// split into sectors and the second-weakest sector counts, so lawn grain
/// cancels out and a zone edge or the dish rim grazing one side scores low.
/// Candidates come from a downscaled copy; each is re-scored at full
/// resolution, then fitted to the disk edge.
List<Disk> findDisks(
  GrayImage gray,
  Plate plate,
  double diskMm,
  ZoneAssay assay, {
  double minRelativeScore = 0.1,
}) {
  final r0 = diskMm / 2 / plate.mmPerPx;
  final g = gray.gaussianBlur(1.0);
  final s = math.min(1.0, kCoarseRadiusPx[assay]! / r0);
  final small = s < 1
      ? gray.resize(
          math.max(1, (gray.width * s).round()),
          math.max(1, (gray.height * s).round()),
        )
      : gray;
  final rs = r0 * s;
  final limit = plate.radius * 0.97 - r0 * 1.5;

  // Coarse: best of several sizes, so a wrong plate format or a tilted photo
  // still finds the disks (and the scale check then reports it).
  final sg = small.gaussianBlur(1.0);
  final (sgx, sgy) = _sobel(sg);
  final coarseTaps = [for (final f in kDiskSizeFactors) _RingTaps(rs * f)];
  final coarse = Float32List(small.width * small.height);
  final sizeOf = Uint8List(coarse.length);
  final pcx = plate.cx * s, pcy = plate.cy * s, lim2 = limit * s;
  var top = 0.0;
  for (var y = 0; y < small.height; y++) {
    for (var x = 0; x < small.width; x++) {
      final dx = x - pcx, dy = y - pcy;
      if (dx * dx + dy * dy >= lim2 * lim2) continue;
      var best = 0.0, bi = 0;
      for (var k = 0; k < coarseTaps.length; k++) {
        final v = coarseTaps[k].scoreAt(sg, sgx, sgy, x, y);
        if (v > best) {
          best = v;
          bi = k;
        }
      }
      final i = y * small.width + x;
      coarse[i] = best;
      sizeOf[i] = bi;
      if (best > top) top = best;
    }
  }
  if (top <= 0) return const [];
  final cands = _greedyPeaks(
    coarse,
    small.width,
    1.5 * rs,
    kMaxDiskCandidates,
    0.05 * top,
  );

  // Fine: full resolution in a small window around each candidate.
  final (gx, gy) = _sobel(g);
  final fineTaps = [for (final f in kDiskSizeFactors) _RingTaps(r0 * f)];
  final win = (1 / s).ceil() + 1;
  final fine = <(double, int, int, int)>[];
  for (final (cx, cy) in cands) {
    final fi = sizeOf[cy * small.width + cx];
    final fx0 = (cx / s).round(), fy0 = (cy / s).round();
    var best = (-1.0, fx0, fy0, fi);
    for (var yy = fy0 - win; yy <= fy0 + win; yy++) {
      for (var xx = fx0 - win; xx <= fx0 + win; xx++) {
        final dx = xx - plate.cx, dy = yy - plate.cy;
        if (math.sqrt(dx * dx + dy * dy) >= limit) continue;
        final sc = fineTaps[fi].scoreAt(g, gx, gy, xx, yy);
        if (sc > best.$1) best = (sc, xx, yy, fi);
      }
    }
    if (best.$1 > 0) fine.add(best);
  }
  if (fine.isEmpty) return const [];
  final fineTop = fine.map((f) => f.$1).reduce(math.max);
  final order = List.generate(fine.length, (i) => i)
    ..sort((a, b) {
      final c = fine[b].$1.compareTo(fine[a].$1);
      return c != 0 ? c : a.compareTo(b);
    });
  final disks = <Disk>[];
  for (final i in order) {
    final (sc, x, y, fi) = fine[i];
    if (sc < math.max(minRelativeScore * fineTop, kMinDiskScore)) break;
    final rf = r0 * kDiskSizeFactors[fi];
    if (disks.any((d) => _hypot(x - d.x, y - d.y) < 3 * rf)) continue;
    final (fx, fy, r, ok) = _refineDisk(g, x.toDouble(), y.toDouble(), rf);
    disks.add(Disk(fx, fy, r, score: sc, measured: ok));
  }
  return disks;
}

/// Strongest pixels first, at least [minDist] apart, up to [limit].
List<(int, int)> _greedyPeaks(
  Float32List score,
  int width,
  double minDist,
  int limit,
  double floor,
) {
  final idx = <int>[
    for (var i = 0; i < score.length; i++)
      if (score[i] > floor) i,
  ];
  idx.sort((a, b) {
    final c = score[b].compareTo(score[a]);
    return c != 0 ? c : a.compareTo(b);
  });
  final out = <(int, int)>[];
  final md2 = minDist * minDist;
  for (final i in idx) {
    final x = i % width, y = i ~/ width;
    if (out.any(
      (o) => (x - o.$1) * (x - o.$1) + (y - o.$2) * (y - o.$2) < md2,
    )) {
      continue;
    }
    out.add((x, y));
    if (out.length >= limit) break;
  }
  return out;
}

/// Sample points of the ring score around a centre at the origin (see
/// ring_taps in zones.py). Weights average within each sector.
class _RingTaps {
  factory _RingTaps(double r0) {
    final k = (r0 + kRidgeGapPx + 2).ceil();
    final n = 2 * k + 1;
    final sector = Int32List(n * n);
    final dist = Float64List(n * n);
    final theta = Float64List(n * n);
    for (var yy = -k; yy <= k; yy++) {
      for (var xx = -k; xx <= k; xx++) {
        final i = (yy + k) * n + (xx + k);
        dist[i] = math.sqrt((xx * xx + yy * yy).toDouble());
        theta[i] = math.atan2(yy.toDouble(), xx.toDouble());
        sector[i] =
            ((theta[i] + math.pi) / (2 * math.pi) * kRingSectors).floor() %
            kRingSectors;
      }
    }
    Float64List ring(double r) {
      final w = Float64List(n * n);
      final counts = Int32List(kRingSectors);
      for (var i = 0; i < n * n; i++) {
        if ((dist[i] - r).abs() <= 1.0) counts[sector[i]]++;
      }
      for (var i = 0; i < n * n; i++) {
        if ((dist[i] - r).abs() <= 1.0) w[i] = 1.0 / counts[sector[i]];
      }
      return w;
    }

    final w0 = ring(r0);
    final wIn = ring(r0 - kRidgeGapPx), wOut = ring(r0 + kRidgeGapPx);
    final sdx = <int>[], sdy = <int>[], ssec = <int>[];
    final scos = <double>[], ssin = <double>[];
    final rdx = <int>[], rdy = <int>[], rsec = <int>[];
    final rw = <double>[];
    for (var yy = -k; yy <= k; yy++) {
      for (var xx = -k; xx <= k; xx++) {
        final i = (yy + k) * n + (xx + k);
        if (w0[i] > 0) {
          sdx.add(xx);
          sdy.add(yy);
          ssec.add(sector[i]);
          scos.add(math.cos(theta[i]) * w0[i]);
          ssin.add(math.sin(theta[i]) * w0[i]);
        }
        final wr = w0[i] - 0.5 * wIn[i] - 0.5 * wOut[i];
        if (wr != 0) {
          rdx.add(xx);
          rdy.add(yy);
          rsec.add(sector[i]);
          rw.add(wr);
        }
      }
    }
    return _RingTaps._(
      k,
      Int32List.fromList(sdx),
      Int32List.fromList(sdy),
      Int32List.fromList(ssec),
      Float64List.fromList(scos),
      Float64List.fromList(ssin),
      Int32List.fromList(rdx),
      Int32List.fromList(rdy),
      Int32List.fromList(rsec),
      Float64List.fromList(rw),
    );
  }

  _RingTaps._(
    this.k,
    this.sdx,
    this.sdy,
    this.ssec,
    this.scos,
    this.ssin,
    this.rdx,
    this.rdy,
    this.rsec,
    this.rw,
  );

  final int k;
  final Int32List sdx, sdy, ssec, rdx, rdy, rsec;
  final Float64List scos, ssin, rw;
  final Float64List _st = Float64List(kRingSectors);
  final Float64List _rd = Float64List(kRingSectors);

  double scoreAt(GrayImage g, Float32List gx, Float32List gy, int x, int y) {
    final w = g.width, h = g.height;
    _st.fillRange(0, kRingSectors, 0);
    _rd.fillRange(0, kRingSectors, 0);
    final inside = x - k >= 0 && x + k < w && y - k >= 0 && y + k < h;
    final base = y * w + x;
    for (var t = 0; t < sdx.length; t++) {
      final i = inside
          ? base + sdy[t] * w + sdx[t]
          : (y + sdy[t]).clamp(0, h - 1) * w + (x + sdx[t]).clamp(0, w - 1);
      _st[ssec[t]] += gx[i] * scos[t] + gy[i] * ssin[t];
    }
    for (var t = 0; t < rdx.length; t++) {
      final i = inside
          ? base + rdy[t] * w + rdx[t]
          : (y + rdy[t]).clamp(0, h - 1) * w + (x + rdx[t]).clamp(0, w - 1);
      _rd[rsec[t]] += g.data[i] * rw[t];
    }
    return 3 * _allRound(_st) + _allRound(_rd);
  }
}

/// Second-weakest sector in the dominant direction (0 if the sectors disagree).
double _allRound(Float64List v) {
  final s = Float64List.fromList(v)..sort();
  return math.max(math.max(s[1], 0), math.max(-s[s.length - 2], 0));
}

/// 3x3 Sobel derivatives divided by 8 (brightness change per pixel).
(Float32List, Float32List) _sobel(GrayImage g) {
  final w = g.width, h = g.height, d = g.data;
  final gx = Float32List(w * h), gy = Float32List(w * h);
  for (var y = 0; y < h; y++) {
    final ym = y > 0 ? y - 1 : 0, yp = y < h - 1 ? y + 1 : h - 1;
    for (var x = 0; x < w; x++) {
      final xm = x > 0 ? x - 1 : 0, xp = x < w - 1 ? x + 1 : w - 1;
      final a = d[ym * w + xm], b = d[ym * w + x], c = d[ym * w + xp];
      final l = d[y * w + xm], r = d[y * w + xp];
      final e = d[yp * w + xm], f = d[yp * w + x], gg = d[yp * w + xp];
      gx[y * w + x] = ((c + 2 * r + gg) - (a + 2 * l + e)) / 8;
      gy[y * w + x] = ((e + 2 * f + gg) - (a + 2 * b + c)) / 8;
    }
  }
  return (gx, gy);
}

/// Bilinear sample with the border replicated.
double _sample(GrayImage g, double x, double y) {
  final w = g.width, h = g.height;
  final fx = x.clamp(0.0, w - 1.0), fy = y.clamp(0.0, h - 1.0);
  final x0 = fx.floor(), y0 = fy.floor();
  final x1 = math.min(x0 + 1, w - 1), y1 = math.min(y0 + 1, h - 1);
  final tx = fx - x0, ty = fy - y0;
  final d = g.data;
  final a = d[y0 * w + x0], b = d[y0 * w + x1];
  final c = d[y1 * w + x0], e = d[y1 * w + x1];
  return (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + e * tx) * ty;
}

double _hypot(num a, num b) => math.sqrt(a * a + b * b);

/// Centre and radius of the disk edge near (x, y): the steepest brightness
/// change on 72 short rays, fitted with a circle (twice, from the new centre).
(double, double, double, bool) _refineDisk(
  GrayImage g,
  double x,
  double y,
  double r0,
) {
  const n = 72;
  final ts = <double>[];
  for (var t = r0 * 0.7; t < r0 * 1.4; t += 0.25) {
    ts.add(t);
  }
  var cx = x, cy = y, r = r0;
  var ok = false;
  for (var pass = 0; pass < 2; pass++) {
    final ex = Float64List(n), ey = Float64List(n);
    for (var i = 0; i < n; i++) {
      final a = 2 * math.pi * i / n;
      final ca = math.cos(a), sa = math.sin(a);
      var prev = _sample(g, cx + ca * ts[0], cy + sa * ts[0]);
      var bestD = -1.0;
      var bestK = 0;
      for (var k = 1; k < ts.length; k++) {
        final v = _sample(g, cx + ca * ts[k], cy + sa * ts[k]);
        final dd = (v - prev).abs();
        if (dd > bestD) {
          bestD = dd;
          bestK = k - 1;
        }
        prev = v;
      }
      final rho = ts[bestK] + 0.125;
      ex[i] = cx + ca * rho;
      ey[i] = cy + sa * rho;
    }
    var keep = List.filled(n, true);
    var count = n;
    (double, double, double) fit = (0, 0, 0);
    for (var it = 0; it < 3; it++) {
      fit = _fitCircle(ex, ey, keep);
      final res = Float64List(n);
      final kept = <double>[];
      for (var i = 0; i < n; i++) {
        res[i] = (_hypot(ex[i] - fit.$1, ey[i] - fit.$2) - fit.$3).abs();
        if (keep[i]) kept.add(res[i]);
      }
      final thr = math.max(2.0, 2.5 * median(kept));
      keep = [for (var i = 0; i < n; i++) res[i] < thr];
      count = keep.where((k) => k).length;
      if (count < 24) break;
    }
    if (count < 24) break;
    final (fx, fy, fr) = _fitCircle(ex, ey, keep);
    if (!(fr.isFinite &&
        fr >= 0.7 * r0 &&
        fr <= 1.4 * r0 &&
        _hypot(fx - x, fy - y) < 0.3 * r0)) {
      break;
    }
    (cx, cy, r, ok) = (fx, fy, fr, true);
  }
  return (cx, cy, r, ok);
}

/// Algebraic least-squares circle (Kåsa) through the points with [keep] set.
(double, double, double) _fitCircle(
  List<double> x,
  List<double> y,
  List<bool> keep,
) {
  // Centred coordinates keep the normal equations well conditioned.
  var mx = 0.0, my = 0.0, n = 0;
  for (var i = 0; i < x.length; i++) {
    if (!keep[i]) continue;
    mx += x[i];
    my += y[i];
    n++;
  }
  if (n < 3) return (double.nan, double.nan, double.nan);
  mx /= n;
  my /= n;
  var suu = 0.0, svv = 0.0, suv = 0.0, su = 0.0, sv = 0.0;
  var bu = 0.0, bv = 0.0, b1 = 0.0;
  for (var i = 0; i < x.length; i++) {
    if (!keep[i]) continue;
    final u = x[i] - mx, v = y[i] - my;
    final b = u * u + v * v;
    suu += u * u;
    svv += v * v;
    suv += u * v;
    su += u;
    sv += v;
    bu += u * b;
    bv += v * b;
    b1 += b;
  }
  // Solve [suu suv su; suv svv sv; su sv n] [a b c]' = [bu bv b1]'.
  final m = [
    [suu, suv, su, bu],
    [suv, svv, sv, bv],
    [su, sv, n.toDouble(), b1],
  ];
  for (var c = 0; c < 3; c++) {
    var p = c;
    for (var r = c + 1; r < 3; r++) {
      if (m[r][c].abs() > m[p][c].abs()) p = r;
    }
    final t = m[c];
    m[c] = m[p];
    m[p] = t;
    if (m[c][c].abs() < 1e-12) return (double.nan, double.nan, double.nan);
    for (var r = 0; r < 3; r++) {
      if (r == c) continue;
      final f = m[r][c] / m[c][c];
      for (var k = c; k < 4; k++) {
        m[r][k] -= f * m[c][k];
      }
    }
  }
  final a = m[0][3] / m[0][0], b = m[1][3] / m[1][1], c = m[2][3] / m[2][2];
  final ucx = a / 2, ucy = b / 2;
  final rr = math.sqrt(math.max(c + ucx * ucx + ucy * ucy, 0));
  return (ucx + mx, ucy + my, rr);
}

// ---------------------------------------------------------------------------
// Measuring zones

class _Rays {
  _Rays(
    this.prof,
    this.lengths,
    this.reasons,
    this.t,
    this.nearLevel,
    this.far,
    this.nFar,
  );

  final List<Float64List> prof;
  final Int32List lengths;
  final List<String> reasons;
  final Float64List t;
  final double nearLevel;
  final List<double> far;
  final int nFar;
}

(List<Zone>, String) _measureAll(
  GrayImage gray,
  Plate plate,
  List<Disk> disks,
  double diskMm,
  ZoneParams params,
) {
  if (disks.isEmpty) return (<Zone>[], 'unknown');
  final mm = plate.mmPerPx;
  final sm = gray.gaussianBlur(math.max(1.0, 0.1 / mm));
  const step = 0.5;
  final rays = [
    for (final d in disks) _cast(sm, plate, d, disks, step, params),
  ];

  // Lawn level: far ends of rays that reached open lawn (not stopped early).
  final near = [for (final r in rays) r.nearLevel];
  var far = [for (final r in rays) ...r.far];
  if (far.isEmpty) far = List.of(near);
  final lawn = median(List.of(far));
  final diffs = [for (final n in near) lawn - n];
  final strong = [
    for (final d in diffs)
      if (d.abs() >= params.minContrast) d,
  ];
  final sign = median(strong.isNotEmpty ? strong : List.of(diffs)) >= 0
      ? 1.0
      : -1.0;
  final polarity = sign > 0 ? 'dark_zone' : 'bright_zone';

  // Clear-agar level as a fraction of the local lawn, from the clearest zone on
  // the plate (small or hazy zones never clear fully next to the disk). Local
  // lawn: only ray ends that really are lawn.
  final clearest = sign > 0 ? near.reduce(math.min) : near.reduce(math.max);
  final mid = 0.5 * (lawn + clearest);
  final localLawn = <double>[];
  for (final r in rays) {
    final f = [
      for (final v in r.far)
        if (sign * (v - mid) > 0) v,
    ];
    localLawn.add(f.length >= 20 ? median(f) : lawn);
  }
  final ratios = [
    for (var i = 0; i < rays.length; i++)
      rays[i].nearLevel / math.max(localLawn[i], 1e-6),
  ];
  final clearRatio = sign > 0
      ? ratios.reduce(math.min)
      : ratios.reduce(math.max);

  final zones = <Zone>[];
  for (var i = 0; i < disks.length; i++) {
    final clear = clearRatio * localLawn[i];
    final margin = 0.1 * (lawn - clearest).abs();
    final lo = sign > 0
        ? math.min(rays[i].nearLevel, math.max(clear, clearest - margin))
        : math.max(rays[i].nearLevel, math.min(clear, clearest + margin));
    zones.add(
      _measureOne(disks[i], rays[i], lawn, lo, sign, diskMm, mm, step, params),
    );
  }

  // Zones whose circles cross each other: the reading on the shared side is lost.
  for (var i = 0; i < zones.length; i++) {
    for (var j = i + 1; j < zones.length; j++) {
      final a = zones[i], b = zones[j];
      if (!a.radiusPx.isFinite || !b.radiusPx.isFinite) continue;
      if (a.flags.contains('no_zone') || b.flags.contains('no_zone')) continue;
      if (_hypot(a.x - b.x, a.y - b.y) < a.radiusPx + b.radiusPx - 0.5 / mm) {
        for (final z in [a, b]) {
          if (!z.flags.contains('overlap')) z.flags.add('overlap');
        }
      }
    }
  }
  return (zones, polarity);
}

List<double> _rayAngles() => [
  for (var i = 0; i < kZoneRays; i++) 2 * math.pi * i / kZoneRays,
];

_Rays _cast(
  GrayImage sm,
  Plate plate,
  Disk disk,
  List<Disk> disks,
  double step,
  ZoneParams params,
) {
  final mm = plate.mmPerPx;
  final start = disk.radiusPx + params.startGapMm / mm;
  final maxLen = params.maxZoneMm / 2 / mm;
  final angles = _rayAngles();
  final n = ((maxLen - start) / step).ceil() + 1;
  final t = Float64List(n);
  for (var k = 0; k < n; k++) {
    t[k] = start + step * k;
  }
  final ox = disk.x - plate.cx, oy = disk.y - plate.cy;
  final rimR = plate.radius * 0.97;
  final prof = <Float64List>[];
  final lengths = Int32List(kZoneRays);
  final reasons = <String>[];
  final nNear = math.max(2, (0.5 / mm / step).floor());
  final nFar = math.max(2, (1.0 / mm / step).floor());
  final nearVals = <double>[];
  final far = <double>[];
  for (var i = 0; i < kZoneRays; i++) {
    final ux = math.cos(angles[i]), uy = math.sin(angles[i]);
    // Ray ends: plate rim, or the nearest other disk in the way.
    final b = ox * ux + oy * uy;
    final c = ox * ox + oy * oy - rimR * rimR;
    final rimT = -b + math.sqrt(math.max(b * b - c, 0));
    var end = math.min(rimT - 0.3 / mm, maxLen);
    var reason = rimT - 0.3 / mm < maxLen ? 'rim' : 'max';
    for (final o in disks) {
      if (identical(o, disk)) continue;
      final vx = o.x - disk.x, vy = o.y - disk.y;
      final tt = vx * ux + vy * uy;
      final perp2 = vx * vx + vy * vy - tt * tt;
      final rr = math.pow(o.radiusPx + params.startGapMm / mm, 2).toDouble();
      if (tt > 0 && perp2 < rr) {
        final tIn = tt - math.sqrt(math.max(rr - perp2, 0));
        if (tIn < end) {
          end = tIn;
          reason = 'neighbour';
        }
      }
    }
    var len = 0;
    while (len < n && t[len] <= end) {
      len++;
    }
    final p = Float64List(len);
    for (var k = 0; k < len; k++) {
      p[k] = _sample(sm, disk.x + ux * t[k], disk.y + uy * t[k]);
    }
    prof.add(p);
    lengths[i] = len;
    reasons.add(reason);
    for (var k = 0; k < math.min(nNear, len); k++) {
      nearVals.add(p[k]);
    }
    if (reason != 'neighbour' && len > nFar + nNear) {
      for (var k = len - nFar; k < len; k++) {
        far.add(p[k]);
      }
    }
  }
  return _Rays(
    prof,
    lengths,
    reasons,
    t,
    nearVals.isEmpty ? double.nan : median(nearVals),
    far,
    nFar,
  );
}

Zone _measureOne(
  Disk disk,
  _Rays ray,
  double lawn,
  double zoneLevel,
  double sign,
  double diskMm,
  double mm,
  double step,
  ZoneParams params,
) {
  Zone noZone() => Zone(
    x: disk.x,
    y: disk.y,
    diskRadiusPx: disk.radiusPx,
    radiusPx: disk.radiusPx,
    diameterMm: diskMm,
    confidence: 1,
    edgeWidthMm: 0,
    flags: ['no_zone'],
  );
  if (!(sign * (lawn - ray.nearLevel) >= params.minContrast)) return noZone();
  final contrast = sign * (lawn - zoneLevel);
  final persist = math.max(2, (params.persistMm / mm / step).floor());
  final edges = Float64List(kZoneRays)..fillRange(0, kZoneRays, double.nan);
  final widths = <double>[];
  var spikes = 0;
  var blockedRim = 0, blockedNeighbour = 0;
  final t = ray.t;
  for (var i = 0; i < kZoneRays; i++) {
    final len = ray.lengths[i];
    final reason = ray.reasons[i];
    if (len < 3) {
      if (reason == 'neighbour') {
        blockedNeighbour++;
      } else {
        blockedRim++;
      }
      continue;
    }
    final p = Float64List(len);
    for (var k = 0; k < len; k++) {
      p[k] = sign * ray.prof[i][k];
    }
    var hi = sign * lawn;
    if (reason != 'neighbour' && len > ray.nFar + 2) {
      final tail = median([for (var k = len - ray.nFar; k < len; k++) p[k]]);
      if (tail - sign * zoneLevel > 0.5 * contrast) hi = tail;
    }
    final lo = sign * zoneLevel;
    final span = math.max(hi - lo, 1e-6);
    final g = Float64List(len);
    final above = List<bool>.filled(len, false);
    for (var k = 0; k < len; k++) {
      g[k] = (p[k] - lo) / span;
      above[k] = g[k] >= params.edgeLevel;
    }
    final j = _firstPersistent(above, persist);
    if (j == null) {
      if (reason == 'rim') blockedRim++;
      if (reason == 'neighbour') blockedNeighbour++;
      continue;
    }
    if (above.take(j).any((a) => a)) spikes++;
    if (j == 0) {
      edges[i] = t[0];
    } else {
      final g0 = g[j - 1], g1 = g[j];
      final f = g1 != g0 ? (params.edgeLevel - g0) / (g1 - g0) : 0.0;
      edges[i] = t[j - 1] + f * step;
    }
    final loI = _crossingBefore(g, 0.2, j);
    final hiI = _crossingAfter(g, 0.8, j);
    if (loI != null && hiI != null) widths.add((hiI - loI) * step * mm);
  }

  Zone unmeasured() => Zone(
    x: disk.x,
    y: disk.y,
    diskRadiusPx: disk.radiusPx,
    radiusPx: double.nan,
    diameterMm: double.nan,
    confidence: 0,
    edgeWidthMm: 0,
    flags: [
      'unmeasured',
      'low_confidence',
      if (blockedNeighbour > 0.1 * kZoneRays) 'overlap',
      if (blockedRim > 0.1 * kZoneRays) 'hits_rim',
    ],
  );

  final ok = [
    for (var i = 0; i < kZoneRays; i++)
      if (edges[i].isFinite) i,
  ];
  if (ok.length < kZoneRays * kMinAgreeing) return unmeasured();
  final angles = _rayAngles();
  final ex = [for (final i in ok) disk.x + math.cos(angles[i]) * edges[i]];
  final ey = [for (final i in ok) disk.y + math.sin(angles[i]) * edges[i]];
  final rho = [for (final i in ok) edges[i]];
  final med = median(List.of(rho));
  final tol = math.max(0.4 / mm, 3.0);
  var inl = [for (final r in rho) (r - med).abs() < tol];
  var cx = disk.x, cy = disk.y;
  var sumIn = 0.0, nIn = 0;
  for (var i = 0; i < rho.length; i++) {
    if (inl[i]) {
      sumIn += rho[i];
      nIn++;
    }
  }
  var rad = sumIn / nIn;
  int countOf(List<bool> b) => b.where((v) => v).length;
  if (countOf(inl) >= 12) {
    var (fx, fy, fr) = _fitCircle(ex, ey, inl);
    if (_hypot(fx - disk.x, fy - disk.y) < 1.0 / mm) {
      inl = [
        for (var i = 0; i < ex.length; i++)
          (_hypot(ex[i] - fx, ey[i] - fy) - fr).abs() < tol,
      ];
      if (countOf(inl) >= 12) {
        (fx, fy, fr) = _fitCircle(ex, ey, inl);
        if (_hypot(fx - disk.x, fy - disk.y) < 1.0 / mm) {
          (cx, cy, rad) = (fx, fy, fr);
        }
      }
    }
  }
  final confidence = countOf(inl) / kZoneRays;
  if (confidence < kMinAgreeing) return unmeasured();
  final width = widths.isEmpty ? 0.0 : median(widths);
  final diameter = 2 * rad * mm;
  if (diameter - diskMm < 2 * params.startGapMm + 0.3) return noZone();
  return Zone(
    x: cx,
    y: cy,
    diskRadiusPx: disk.radiusPx,
    radiusPx: rad,
    diameterMm: diameter,
    confidence: confidence,
    edgeWidthMm: width,
    flags: [
      if (blockedNeighbour > 0.1 * kZoneRays) 'overlap',
      if (blockedRim > 0.1 * kZoneRays) 'hits_rim',
      if (width > params.hazyWidthMm) 'hazy',
      if (spikes > 0.05 * kZoneRays) 'colonies_in_zone',
      if (confidence < 0.6) 'low_confidence',
    ],
  );
}

int? _firstPersistent(List<bool> above, int persist) {
  final n = above.length;
  if (n == 0) return null;
  var run = 0;
  for (var j = 0; j < n; j++) {
    run = above[j] ? run + 1 : 0;
    if (run >= persist) return j - persist + 1;
  }
  // Edge too close to the end of the ray to confirm the full persistence.
  if (run >= 3) return n - run;
  return null;
}

double? _crossingBefore(Float64List g, double level, int j) {
  for (var k = j; k > 0; k--) {
    if (g[k - 1] < level && level <= g[k]) {
      return k - 1 + (level - g[k - 1]) / (g[k] - g[k - 1]);
    }
  }
  return null;
}

double? _crossingAfter(Float64List g, double level, int j) {
  for (var k = math.max(j, 1); k < g.length; k++) {
    if (g[k - 1] < level && level <= g[k]) {
      return k - 1 + (level - g[k - 1]) / (g[k] - g[k - 1]);
    }
  }
  return null;
}
