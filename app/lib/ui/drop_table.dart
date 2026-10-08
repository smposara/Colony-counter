import 'package:flutter/material.dart';

import '../core/drop_stats.dart';
import '../data/drop_results.dart';
import '../l10n/l10n.dart';
import '../l10n/labels.dart';
import 'format.dart';

/// "10⁻⁵ · 12 15 9 14 11 · mean 12.2 ± 2.4 · VMR 0.50".
String dropRowText(DilutionRow r) => [
  dilutionLabel(r.dilutionExp),
  [
    ...r.counts.map((c) => '$c'),
    if (r.tntc > 0) r.tntc == 1 ? 'TNTC' : 'TNTC ×${r.tntc}',
  ].join(' '),
  if (r.counts.isNotEmpty)
    tr.dropRowMean(
      r.counts.length > 1
          ? '${fixed(r.mean, 1)} ± ${fixed(r.sd, 1)}'
          : fixed(r.mean, 1),
    ),
  if (r.counts.length > 1) 'VMR ${fixed(r.vmr)}',
  if (r.excluded > 0) tr.dropRowLeftOut(r.excluded),
].join(' · ');

/// Which drops CFU/mL came from, and its 95 % interval.
String dropUsedText(DropEstimate e, DropMode mode) {
  if (e.dilutionsUsed.isEmpty) return '';
  final dils = e.dilutionsUsed.map(dilutionLabel).join(', ');
  // Outside the window (an estimate, a "<" limit or a ">" bound) neither
  // calculation applies: just which drops it came from.
  if (e.qualifier != 'exact') return tr.dropUsedFrom(dils, e.dropsUsed);
  return mode == DropMode.first
      ? tr.dropUsedFirst(dils, e.dropsUsed)
      : tr.dropUsedPooled(dils, e.dropsUsed);
}

String dropWarningText(String code, DropSummary s) => switch (code) {
  'overdispersed' => tr.dropWarnOverdispersed,
  'outlier_drop' => tr.dropWarnOutlier,
  'not_tenfold' => tr.dropWarnNotTenfold,
  'crowded_drops' => tr.dropWarnCrowded,
  'drops_not_as_planned' => tr.dropWarnNotAsPlanned(s.found, s.planned),
  'layout_uncertain' => tr.flagLayoutUncertain,
  _ => code,
};

/// The drop table: one line per dilution, then CFU/mL with the drops it
/// came from and its Poisson 95 % interval, then anything to check.
class DropTableView extends StatelessWidget {
  const DropTableView({
    super.key,
    required this.rows,
    required this.estimate,
    required this.mode,
    required this.window,
    this.factor = 1,
    this.unit = 'CFU/mL',
    this.summary,
    this.showEstimate = true,
  });

  final List<DilutionRow> rows;
  final DropEstimate estimate;
  final DropMode mode;
  final (int, int) window;

  /// From CFU/mL to [unit].
  final double factor;
  final String unit;

  /// The whole sample's drops, for its warnings.
  final DropSummary? summary;
  final bool showEstimate;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final used = estimate.dilutionsUsed.toSet();
    final e = estimateOfDrops(estimate, window);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr.dropTableTitle, style: t.titleSmall),
        const SizedBox(height: 4),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    dropRowText(r),
                    style: t.bodyMedium?.copyWith(
                      fontWeight: used.contains(r.dilutionExp)
                          ? FontWeight.bold
                          : null,
                    ),
                  ),
                ),
                if (r.flags.isNotEmpty)
                  Icon(Icons.warning_amber_rounded, size: 18, color: c.error),
              ],
            ),
          ),
        if (showEstimate && estimate.cfuPerMl.isFinite) ...[
          const SizedBox(height: 6),
          Text(
            prettySci(estimateText(e, factor: factor, unit: unit)),
            style: t.titleMedium,
          ),
          if (dropUsedText(estimate, mode).isNotEmpty)
            Text(dropUsedText(estimate, mode), style: t.bodySmall),
          if (estimateNote(e).isNotEmpty)
            Text(estimateNote(e), style: t.bodySmall),
          if (estimate.qualifier != '>' && estimate.high.isFinite)
            Text(
              tr.dropCi(
                estimate.low > 0 ? sciValue(estimate.low * factor) : '0',
                sciValue(estimate.high * factor),
              ),
              style: t.bodySmall,
            ),
        ],
        if (summary != null)
          for (final w in summary!.warnings)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, size: 18, color: c.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      dropWarningText(w, summary!),
                      style: t.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}
