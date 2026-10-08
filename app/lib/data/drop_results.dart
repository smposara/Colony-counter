import '../core/calculator.dart';
import '../core/classical.dart';
import '../core/drop_stats.dart';
import '../core/spots.dart';
import '../core/stats.dart';
import 'plate_record.dart';
import 'sample_info.dart';

/// Drop-plate results for a sample: the drop table, CFU/mL with the sample's
/// counting window and calculation, and what to check
/// (docs/DROP_PLATE_IMPLEMENTATION.md, M5).

/// [spots] as counts. Left-out drops, and every drop of a plate with a
/// spreader, are excluded.
List<DropCount> dropCountsFromSpots(
  List<Spot> spots,
  List<Colony> colonies, {
  bool spreader = false,
}) => [
  for (final s in spots)
    DropCount(
      s.dilutionExp,
      s.replicate,
      countInSpot(s, colonies),
      tntc: s.tntc,
      excluded: s.isExcluded || spreader,
    ),
];

/// The drops of [plates] (the latest photo of each time-lapse series).
List<DropCount> dropCountsOf(List<PlateRecord> plates) => [
  for (final p in latestOfSeries(plates))
    if (p.isDropPlate)
      ...dropCountsFromSpots(p.spots, p.colonies, spreader: p.spreader),
];

/// A drop estimate in the form the rest of the app reports.
Estimate estimateOfDrops(DropEstimate e, (int, int) window) => Estimate(
  e.cfuPerMl.isFinite ? roundSig(e.cfuPerMl) : e.cfuPerMl,
  switch (e.qualifier) {
    'exact' => Qualifier.exact,
    '<' => Qualifier.lessThan,
    '>' => Qualifier.greaterThan,
    _ => Qualifier.estimated,
  },
  CountingRule.dropPlate,
  const [],
  e.note,
  window,
);

/// Drop volume of [plates] in µL (as saved on them), else the plan's.
double _volumeUl(SampleInfo info, List<PlateRecord> plates) {
  for (final p in plates) {
    if (p.isDropPlate && p.volumeMl > 0) return p.volumeMl * 1000;
  }
  return info.dropVolumeUl;
}

/// Per-replicate CFU/mL of a drop sample: each replicate's drops go through
/// the drop table and [estimateDrops] with the sample's window and mode.
SampleResult analyseDrops(SampleInfo info, List<PlateRecord> plates) {
  final byRep = <int, List<DropCount>>{};
  for (final d in dropCountsOf(plates)) {
    (byRep[d.replicate] ??= []).add(d);
  }
  final volume = _volumeUl(info, plates);
  final keys = byRep.keys.toList()..sort();
  return SampleResult({
    for (final k in keys)
      k: estimateOfDrops(
        estimateDrops(
          dilutionTable(byRep[k]!),
          volume,
          mode: info.dropMode,
          window: info.dropWindow,
        ),
        info.dropWindow,
      ),
  }, CountingRule.dropPlate);
}

/// The whole sample's drops: one table row per dilution, CFU/mL over all of
/// them with its Poisson interval, and warnings.
class DropSummary {
  DropSummary({
    required this.rows,
    required this.estimate,
    required this.mode,
    required this.window,
    required this.planned,
    required this.found,
    required this.excluded,
    required this.warnings,
  });

  final List<DilutionRow> rows;
  final DropEstimate estimate;
  final DropMode mode;
  final (int, int) window;

  /// Drops planned over the sample's plates so far, found on them (counted
  /// or not), and left out.
  final int planned;
  final int found;
  final int excluded;

  /// What to check: `overdispersed`, `outlier_drop`, `not_tenfold`,
  /// `crowded_drops`, `drops_not_as_planned`, `layout_uncertain`.
  final List<String> warnings;

  Estimate get asEstimate => estimateOfDrops(estimate, window);

  bool get isEmpty => rows.isEmpty;
}

DropSummary dropSummary(SampleInfo info, List<PlateRecord> plates) {
  final latest = [
    for (final p in latestOfSeries(plates))
      if (p.isDropPlate) p,
  ];
  final rows = dilutionTable(dropCountsOf(latest));
  final estimate = estimateDrops(
    rows,
    _volumeUl(info, latest),
    mode: info.dropMode,
    window: info.dropWindow,
  );
  final spots = [for (final p in latest) ...p.spots];
  final counted = [
    for (final p in latest)
      if (!p.spreader)
        for (final s in p.spots)
          if (!s.isExcluded) s,
  ];
  final planned = latest.length * info.dropsPerPlate;
  final rowFlags = {for (final r in rows) ...r.flags};
  return DropSummary(
    rows: rows,
    estimate: estimate,
    mode: info.dropMode,
    window: info.dropWindow,
    planned: planned,
    found: spots.length,
    excluded: spots.where((s) => s.isExcluded).length,
    warnings: [
      for (final f in const ['overdispersed', 'outlier_drop', 'not_tenfold'])
        if (rowFlags.contains(f)) f,
      if (counted.any((s) => s.flags.contains('crowded'))) 'crowded_drops',
      if (spots.any((s) => s.flags.contains('unplanned')) ||
          latest.any((p) => p.spots.length != info.dropsPerPlate))
        'drops_not_as_planned',
      if (latest.any((p) => p.flags.contains('layout_uncertain')))
        'layout_uncertain',
    ],
  );
}
