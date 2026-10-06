import 'dart:math' as math;

/// CFU/mL from plate counts (mirrors ml/colonycounter/calculator.py).
///
/// Pooled (weighted-mean) estimate over countable plates:
///   N = ΣC / Σ(V_i × d_i)
/// which equals the ISO 7218 form ΣC / (V × (n1 + 0.1·n2) × d) for two
/// successive tenfold dilutions.

/// Countable range per plate (inclusive). Check against your lab SOP.
enum CountingRule {
  fdaBam('FDA BAM', 25, 250),
  iso7218('ISO 7218', 10, 300),
  range30to300('30–300', 30, 300),

  /// Drop plates (Miles–Misra): colonies per 10–20 µL spot.
  dropPlate('Drop 3–30', 3, 30),

  /// Membrane filters: 20–80 for coliforms / E. coli, 20–200 for total counts.
  membrane80('Membrane 20–80', 20, 80),
  membrane200('Membrane 20–200', 20, 200);

  const CountingRule(this.label, this.min, this.max);

  final String label;
  final int min;
  final int max;

  /// Rules a user can choose for whole (spread / pour) plates.
  static const spreadRules = [fdaBam, iso7218, range30to300];
  static const membraneRules = [membrane80, membrane200];
}

class PlateCount {
  const PlateCount(
    this.count,
    this.dilution, {
    this.volumeMl = 0.1,
    this.spreader = false,
    this.tntc = false,
  });

  final int count;

  /// Dilution of the plated suspension, e.g. 1e-4 for the 10⁻⁴ tube.
  final double dilution;
  final double volumeMl;
  final bool spreader;

  /// Too numerous to count; [count] is a lower bound.
  final bool tntc;
}

enum Qualifier { exact, estimated, lessThan, greaterThan }

class Estimate {
  Estimate(
    this.value,
    this.qualifier,
    this.rule,
    this.platesUsed, [
    this.note = '',
  ]);

  final double value;
  final Qualifier qualifier;
  final CountingRule rule;
  final List<PlateCount> platesUsed;
  final String note;

  @override
  String toString() => describe();

  /// e.g. "est. 1.2 × 10^4 CFU/mL"; [factor] rescales for other units, e.g.
  /// 100 for CFU/100 mL.
  String describe({double factor = 1, String unit = 'CFU/mL'}) {
    if (value.isNaN) return 'no estimate';
    final q = switch (qualifier) {
      Qualifier.exact => '',
      Qualifier.estimated => 'est. ',
      Qualifier.lessThan => '< ',
      Qualifier.greaterThan => '> ',
    };
    return '$q${formatSci(value * factor)} $unit';
  }
}

double cfuPerMl(num count, double dilution, double volumeMl) {
  if (dilution <= 0 || volumeMl <= 0) {
    throw ArgumentError('dilution and volume must be positive');
  }
  return count / (volumeMl * dilution);
}

double roundSig(double x, [int sig = 2]) {
  if (x == 0 || !x.isFinite) return x;
  final e = (math.log(x.abs()) / math.ln10).floor();
  final f = math.pow(10, sig - 1 - e).toDouble();
  return (x * f).round() / f;
}

/// e.g. 16545 -> "1.7 × 10^4" (two significant figures by default).
String formatSci(double x, [int sig = 2]) {
  if (x == 0) return '0';
  if (!x.isFinite) return '—';
  var e = (math.log(x.abs()) / math.ln10).floor();
  var mant = roundSig(x, sig) / math.pow(10, e);
  if (mant.abs() >= 10) {
    mant /= 10;
    e += 1;
  }
  return '${mant.toStringAsFixed(sig - 1)} × 10^$e';
}

/// CFU/mL from one or more plates of a dilution series. [sampleFactor] converts
/// to the original sample if that step is not already part of [PlateCount.dilution].
Estimate estimate(
  List<PlateCount> plates, {
  CountingRule rule = CountingRule.fdaBam,
  double sampleFactor = 1,
}) {
  final lo = rule.min, hi = rule.max;
  final usable = [
    for (final p in plates)
      if (!p.spreader) p,
  ];
  if (usable.isEmpty) {
    return Estimate(
      double.nan,
      Qualifier.estimated,
      rule,
      [],
      'all plates have spreaders',
    );
  }

  final inRange = [
    for (final p in usable)
      if (p.count >= lo && p.count <= hi && !p.tntc) p,
  ];
  if (inRange.isNotEmpty) {
    final total = inRange.fold<int>(0, (s, p) => s + p.count);
    final denom = inRange.fold<double>(
      0,
      (s, p) => s + p.volumeMl * p.dilution,
    );
    return Estimate(
      roundSig(total / denom * sampleFactor),
      Qualifier.exact,
      rule,
      inRange,
    );
  }

  final above = [
    for (final p in usable)
      if (p.count > hi || p.tntc) p,
  ];
  final below = [
    for (final p in usable)
      if (p.count < lo && !p.tntc) p,
  ];
  double vd(PlateCount p) => p.volumeMl * p.dilution;

  if (below.isNotEmpty && above.isEmpty) {
    final p = below.reduce((a, b) => vd(a) >= vd(b) ? a : b); // least diluted
    if (p.count == 0) {
      final v = cfuPerMl(1, p.dilution, p.volumeMl) * sampleFactor;
      return Estimate(roundSig(v), Qualifier.lessThan, rule, [
        p,
      ], 'no colonies on least diluted plate');
    }
    final v = cfuPerMl(p.count, p.dilution, p.volumeMl) * sampleFactor;
    return Estimate(roundSig(v), Qualifier.estimated, rule, [
      p,
    ], 'below countable range ($lo–$hi)');
  }

  if (above.isNotEmpty && below.isEmpty) {
    final p = above.reduce((a, b) => vd(a) <= vd(b) ? a : b); // most diluted
    final v = cfuPerMl(p.count, p.dilution, p.volumeMl) * sampleFactor;
    if (p.tntc) {
      return Estimate(roundSig(v), Qualifier.greaterThan, rule, [
        p,
      ], 'too numerous to count');
    }
    return Estimate(roundSig(v), Qualifier.estimated, rule, [
      p,
    ], 'above countable range ($lo–$hi)');
  }

  // Neighbouring dilutions straddle the range: take the count closest to it.
  // A TNTC count is only a lower bound, so it never counts as close; `below`
  // is not empty here, so there is always a real count to use.
  int gap(PlateCount p) => p.count < lo ? lo - p.count : p.count - hi;
  final p = [
    for (final q in usable)
      if (!q.tntc) q,
  ].reduce((a, b) => gap(a) <= gap(b) ? a : b);
  final v = cfuPerMl(p.count, p.dilution, p.volumeMl) * sampleFactor;
  return Estimate(roundSig(v), Qualifier.estimated, rule, [
    p,
  ], 'no plate in countable range');
}
