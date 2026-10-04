import 'dart:math' as math;

import 'calculator.dart';

/// Summary statistics across biological / technical replicates.
///
/// Labs usually report log₁₀ CFU/mL as mean ± SD of the replicates' log values,
/// because counts are roughly log-normal; the arithmetic mean ± SD and CV are
/// given too.
class ReplicateStats {
  ReplicateStats(this.values);

  /// One CFU/mL estimate per replicate (NaN-free, positive values only).
  final List<double> values;

  int get n => values.length;
  double get mean => n == 0 ? double.nan : values.reduce((a, b) => a + b) / n;
  double get sd => _sd(values);

  /// Coefficient of variation, in percent.
  double get cvPercent => n < 2 || mean == 0 ? double.nan : sd / mean * 100;

  List<double> get log10Values => [for (final v in values) _log10(v)];
  double get log10Mean =>
      n == 0 ? double.nan : log10Values.reduce((a, b) => a + b) / n;
  double get log10Sd => _sd(log10Values);
}

/// One countable unit (a whole plate, or one spot of a drop plate) tagged with
/// the replicate it belongs to.
class Observation {
  const Observation(this.count, this.replicate);

  final PlateCount count;
  final int replicate;
}

/// Per-replicate CFU/mL: each replicate's units are pooled with [estimate]
/// (so several dilutions of one replicate combine), then summarised.
///
/// Replicates with no usable estimate (all spreaders) are left out; estimates
/// marked "<" or ">" are included at their bound but reported in [qualified].
class SampleResult {
  SampleResult(this.perReplicate, this.rule);

  final Map<int, Estimate> perReplicate;
  final CountingRule rule;

  ReplicateStats get stats => ReplicateStats([
    for (final e in perReplicate.values)
      if (e.value.isFinite && e.value > 0) e.value,
  ]);

  /// True when any replicate is only an estimate (out of range, <, >).
  bool get qualified =>
      perReplicate.values.any((e) => e.qualifier != Qualifier.exact);
}

SampleResult analyseReplicates(List<Observation> obs, CountingRule rule) {
  final byRep = <int, List<PlateCount>>{};
  for (final o in obs) {
    (byRep[o.replicate] ??= []).add(o.count);
  }
  final keys = byRep.keys.toList()..sort();
  return SampleResult({
    for (final k in keys) k: estimate(byRep[k]!, rule: rule),
  }, rule);
}

/// Treated vs control, from per-replicate CFU/mL.
class Reduction {
  Reduction(this.control, this.treated);

  final ReplicateStats control;
  final ReplicateStats treated;

  /// log₁₀ reduction = mean log₁₀(control) − mean log₁₀(treated).
  double get logReduction => control.log10Mean - treated.log10Mean;

  /// SD of the log reduction, combining both groups' SDs.
  double get logReductionSd {
    final a = control.n > 1 ? control.log10Sd : 0.0;
    final b = treated.n > 1 ? treated.log10Sd : 0.0;
    return math.sqrt(a * a + b * b);
  }

  /// Percent killed (or inhibited) relative to control, from the geometric means.
  double get percentKill => (1 - math.pow(10, -logReduction)) * 100;
}

double _log10(double v) => math.log(v) / math.ln10;

double _sd(List<double> v) {
  if (v.length < 2) return double.nan;
  final m = v.reduce((a, b) => a + b) / v.length;
  final ss = v.fold(0.0, (s, x) => s + (x - m) * (x - m));
  return math.sqrt(ss / (v.length - 1));
}
