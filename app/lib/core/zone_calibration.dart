import 'dart:math' as math;

// Calibration of zone measurement against the user's own calliper (or ruler).
// Mirrors ml/colonycounter/zone_calibration.py; keep the two in step (the shared
// cases in test/fixtures/calibration_cases.json check agreement). See
// docs/ZONE_CALIBRATION_IMPLEMENTATION.md.
//
// The user photographs a used zone plate, measures one long span (outer edge of one
// disk to the outer edge of the disk farthest from it) and each zone. This compares
// those readings with the app's measurement: bias, Bland–Altman limits of agreement,
// the scale error from the span, and a hint at the cause. Check only: nothing here
// changes a measurement.

/// Zones at or beyond this fraction of the plate radius count as "near the edge".
const double kOuterFraction = 0.6;

/// The slope of difference against size is only judged when the zones differ in
/// size by at least this much (mm).
const double kMinSizeSpread = 5.0;

enum CalibrationTool { calliper, ruler }

enum CalibrationVerdict { good, usable, poor, tooFew }

/// What most likely explains a result that isn't good.
enum CalibrationHint { none, scale, lens, edge, spread }

class CalibrationLimits {
  const CalibrationLimits(
    this.minZones,
    this.goodBias,
    this.goodLoa,
    this.goodScale,
    this.usableBias,
    this.usableLoa,
  );

  final int minZones;
  final double goodBias;
  final double goodLoa;

  /// Fraction, e.g. 0.01 for 1 %.
  final double goodScale;
  final double usableBias;
  final double usableLoa;

  static const calliper = CalibrationLimits(6, 0.5, 1.0, 0.01, 1.0, 2.0);
  static const ruler = CalibrationLimits(8, 0.5, 1.5, 0.015, 1.0, 2.5);

  static CalibrationLimits of(CalibrationTool t) =>
      t == CalibrationTool.ruler ? ruler : calliper;
}

/// One zone: the app's diameter on each photo and the user's reading(s), in mm.
class CalZone {
  const CalZone({
    required this.appMm,
    required this.userMm,
    this.radialFraction = 0,
    this.included = true,
  });

  final List<double> appMm;
  final List<double> userMm;

  /// Distance from the plate centre / plate radius.
  final double radialFraction;
  final bool included;
}

class CalSummary {
  const CalSummary({
    required this.n,
    required this.bias,
    required this.sd,
    required this.loaLow,
    required this.loaHigh,
    required this.maxAbs,
    required this.within1mm,
    required this.slope,
    required this.slopeSignificant,
    required this.edgeMinusCentre,
    required this.repeatabilitySd,
    required this.scaleError,
    required this.verdict,
    required this.hint,
    required this.differences,
  });

  final int n;

  /// Mean of app − user (mm).
  final double bias;
  final double sd;

  /// 95 % limits of agreement, bias ± 1.96 SD.
  final double loaLow;
  final double loaHigh;
  final double maxAbs;

  /// Fraction of zones within 1 mm.
  final double within1mm;

  /// Of the difference against the mean of the two readings (null: not enough).
  final double? slope;
  final bool slopeSignificant;

  /// Mean difference of zones near the plate edge minus central ones.
  final double? edgeMinusCentre;

  /// Pooled SD of the app's diameter across photos.
  final double? repeatabilitySd;

  /// App span / user span − 1 (null without a span).
  final double? scaleError;
  final CalibrationVerdict verdict;
  final CalibrationHint hint;

  /// App − user per zone used.
  final List<double> differences;
}

double _mean(List<double> v) => v.reduce((a, b) => a + b) / v.length;

double _sd(List<double> v) {
  if (v.length < 2) return double.nan;
  final m = _mean(v);
  return math.sqrt(
    v.fold(0.0, (s, x) => s + (x - m) * (x - m)) / (v.length - 1),
  );
}

/// Indices of the two disks (x, y, r in px) whose outer edges are farthest apart.
(int, int) farthestPair(List<(double, double, double)> disks) {
  var best = -1.0;
  var pair = (0, 1);
  for (var i = 0; i < disks.length; i++) {
    for (var j = i + 1; j < disks.length; j++) {
      final (xa, ya, ra) = disks[i];
      final (xb, yb, rb) = disks[j];
      final span =
          math.sqrt(math.pow(xa - xb, 2) + math.pow(ya - yb, 2)) + ra + rb;
      if (span > best) {
        best = span;
        pair = (i, j);
      }
    }
  }
  return pair;
}

/// Outer edge to outer edge of disks [a] and [b] (x, y, r in px), in mm.
double appSpanMm(
  (double, double, double) a,
  (double, double, double) b,
  double mmPerPx,
) =>
    (math.sqrt(math.pow(a.$1 - b.$1, 2) + math.pow(a.$2 - b.$2, 2)) +
        a.$3 +
        b.$3) *
    mmPerPx;

CalSummary calibrationSummary(
  List<CalZone> zones, {
  double? appSpan,
  double? userSpan,
  CalibrationTool tool = CalibrationTool.calliper,
}) {
  final lim = CalibrationLimits.of(tool);
  final use = [
    for (final z in zones)
      if (z.included &&
          z.appMm.isNotEmpty &&
          z.userMm.isNotEmpty &&
          [...z.appMm, ...z.userMm].every((v) => v.isFinite))
        z,
  ];
  final app = [for (final z in use) _mean(z.appMm)];
  final user = [for (final z in use) _mean(z.userMm)];
  final d = [for (var i = 0; i < use.length; i++) app[i] - user[i]];
  final m = [for (var i = 0; i < use.length; i++) (app[i] + user[i]) / 2];
  final n = d.length;
  final bias = n > 0 ? _mean(d) : double.nan;
  final sd = n >= 2 ? _sd(d) : (n == 1 ? 0.0 : double.nan);
  final loaLow = bias - 1.96 * sd, loaHigh = bias + 1.96 * sd;
  final maxAbs = n > 0 ? d.map((x) => x.abs()).reduce(math.max) : double.nan;
  final within = n > 0
      ? d.where((x) => x.abs() <= 1.0 + 1e-9).length / n
      : double.nan;

  // Difference against size: a slope means the scale is off.
  double? slope;
  var significant = false;
  if (n >= 3) {
    final mm = _mean(m);
    final sxx = m.fold(0.0, (s, x) => s + (x - mm) * (x - mm));
    if (sxx > 1e-12) {
      var sxy = 0.0;
      for (var i = 0; i < n; i++) {
        sxy += (m[i] - mm) * (d[i] - bias);
      }
      final b = sxy / sxx;
      slope = b;
      var rss = 0.0;
      for (var i = 0; i < n; i++) {
        final r = d[i] - (bias + b * (m[i] - mm));
        rss += r * r;
      }
      final s2 = n > 2 ? rss / (n - 2) : 0.0;
      final se = math.sqrt(s2 / sxx);
      final spread = m.reduce(math.max) - m.reduce(math.min);
      final big = b.abs() * spread > 0.5;
      // Zones of similar size can't show a scale error: the mean of the two
      // readings then varies mostly with the difference itself.
      significant =
          n >= 4 &&
          spread >= kMinSizeSpread &&
          big &&
          (se == 0 || b.abs() > 2 * se);
    }
  }

  // Near the plate edge against the centre: lens distortion or tilt.
  final outer = [
    for (var i = 0; i < n; i++)
      if (use[i].radialFraction >= kOuterFraction) d[i],
  ];
  final inner = [
    for (var i = 0; i < n; i++)
      if (use[i].radialFraction < kOuterFraction) d[i],
  ];
  final edge = outer.length >= 2 && inner.length >= 2
      ? _mean(outer) - _mean(inner)
      : null;

  // Repeatability: pooled SD of the app's diameter across photos.
  final multi = [
    for (final z in use)
      if (z.appMm.length >= 2) z.appMm,
  ];
  final rep = multi.isEmpty
      ? null
      : math.sqrt(
          _mean([for (final v in multi) math.pow(_sd(v), 2) as double]),
        );

  final scale =
      appSpan != null && userSpan != null && appSpan != 0 && userSpan != 0
      ? appSpan / userSpan - 1
      : null;

  final CalibrationVerdict verdict;
  if (n < lim.minZones) {
    verdict = CalibrationVerdict.tooFew;
  } else if (bias.abs() <= lim.goodBias &&
      loaLow >= -lim.goodLoa &&
      loaHigh <= lim.goodLoa &&
      (scale == null || scale.abs() <= lim.goodScale)) {
    verdict = CalibrationVerdict.good;
  } else if (bias.abs() <= lim.usableBias &&
      loaLow >= -lim.usableLoa &&
      loaHigh <= lim.usableLoa) {
    verdict = CalibrationVerdict.usable;
  } else {
    verdict = CalibrationVerdict.poor;
  }

  final CalibrationHint hint;
  if (verdict == CalibrationVerdict.good ||
      verdict == CalibrationVerdict.tooFew) {
    hint = CalibrationHint.none;
  } else if ((scale != null && scale.abs() > lim.goodScale) || significant) {
    hint = CalibrationHint.scale;
  } else if (edge != null && edge.abs() > 0.5) {
    hint = CalibrationHint.lens;
  } else if (bias.abs() > 0.5) {
    hint = CalibrationHint.edge;
  } else {
    hint = CalibrationHint.spread;
  }

  return CalSummary(
    n: n,
    bias: bias,
    sd: sd,
    loaLow: loaLow,
    loaHigh: loaHigh,
    maxAbs: maxAbs,
    within1mm: within,
    slope: slope,
    slopeSignificant: significant,
    edgeMinusCentre: edge,
    repeatabilitySd: rep,
    scaleError: scale,
    verdict: verdict,
    hint: hint,
    differences: d,
  );
}
