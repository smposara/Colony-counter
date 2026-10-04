import 'dart:math' as math;

import '../core/pipeline.dart';
import 'plate_record.dart';

/// One plate whose every colony was checked by hand: the automatic count
/// against the checked (reference) count.
class AccuracyPoint {
  AccuracyPoint(this.record)
    : auto = record.autoCount,
      checked = record.count,
      falsePositives = record.rejected.fold(0, (s, c) => s + c.n),
      missed = record.colonies
          .where((c) => c.manual)
          .fold(0, (s, c) => s + c.n),
      warned = record.flags.any(kCheckFlags.contains);

  final PlateRecord record;
  final int auto;
  final int checked;

  /// Automatic marks the user removed.
  final int falsePositives;

  /// Colonies the user added by hand.
  final int missed;

  /// The app had flagged the plate for checking.
  final bool warned;

  int get error => auto - checked;

  /// Signed error in percent of the checked count; null below 10 colonies,
  /// where percentages mean little.
  double? get errorPercent => checked < 10 ? null : error / checked * 100;
}

/// Error statistics over a group of checked plates.
class CountErrors {
  CountErrors(this.points);

  final List<AccuracyPoint> points;

  int get n => points.length;
  List<double> get _pct => [
    for (final p in points)
      if (p.errorPercent != null) p.errorPercent!,
  ];

  /// Mean |auto − checked| in colonies.
  double get meanAbsError =>
      n == 0 ? double.nan : points.fold(0, (s, p) => s + p.error.abs()) / n;

  /// Mean |error| in percent (plates with ≥ 10 colonies).
  double get meanAbsPercent {
    final v = _pct;
    return v.isEmpty
        ? double.nan
        : v.fold(0.0, (s, e) => s + e.abs()) / v.length;
  }

  /// Mean signed error in percent: negative means the app undercounts.
  double get biasPercent {
    final v = _pct;
    return v.isEmpty ? double.nan : v.fold(0.0, (s, e) => s + e) / v.length;
  }

  /// Share of plates (≥ 10 colonies) within ±10 % of the checked count.
  double get within10Percent {
    final v = _pct;
    return v.isEmpty
        ? double.nan
        : v.where((e) => e.abs() <= 10).length / v.length * 100;
  }

  /// Of the automatic marks, the share that were real colonies.
  double get precision {
    final auto = points.fold(0, (s, p) => s + p.auto);
    final fp = points.fold(0, (s, p) => s + p.falsePositives);
    return auto == 0 ? double.nan : (auto - fp) / auto * 100;
  }

  /// Of the checked colonies, the share the app found by itself.
  double get recall {
    final checked = points.fold(0, (s, p) => s + p.checked);
    final missed = points.fold(0, (s, p) => s + p.missed);
    return checked == 0
        ? double.nan
        : math.max(0, checked - missed) / checked * 100;
  }
}

/// Accuracy of the automatic count on the user's own checked plates.
class AccuracyReport {
  AccuracyReport(List<PlateRecord> records)
    : points = [
        for (final r in records)
          if (r.verified && !r.isDropPlate) AccuracyPoint(r),
      ];

  final List<AccuracyPoint> points;

  CountErrors get all => CountErrors(points);

  /// By checked count: under 30, 30–300, over 300.
  Map<String, CountErrors> get byRange => {
    '< 30': CountErrors([
      for (final p in points)
        if (p.checked < 30) p,
    ]),
    '30–300': CountErrors([
      for (final p in points)
        if (p.checked >= 30 && p.checked <= 300) p,
    ]),
    '> 300': CountErrors([
      for (final p in points)
        if (p.checked > 300) p,
    ]),
  };

  /// Plates the app flagged for checking vs the rest: the flagged ones should
  /// have the larger errors if the warnings are useful.
  (CountErrors, CountErrors) get byWarning => (
    CountErrors([
      for (final p in points)
        if (p.warned) p,
    ]),
    CountErrors([
      for (final p in points)
        if (!p.warned) p,
    ]),
  );
}
