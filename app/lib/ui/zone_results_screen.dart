import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/plate_store.dart';
import '../data/zone_record.dart';
import '../l10n/l10n.dart';
import 'chart_colours.dart';
import 'insets.dart';

/// Mean ± SD zone diameter per test item, for one experiment: a bar chart
/// and a table for each test organism. Measurement only: no S/I/R.
class ZoneResultsScreen extends StatefulWidget {
  const ZoneResultsScreen({super.key, required this.store, this.experiment});

  final PlateStore store;

  /// Shown first; defaults to the newest plate's experiment.
  final String? experiment;

  @override
  State<ZoneResultsScreen> createState() => _ZoneResultsScreenState();
}

class _ZoneResultsScreenState extends State<ZoneResultsScreen> {
  PlateStore get store => widget.store;

  /// Experiments with zone plates, in name order ('' for unnamed).
  List<String> get _experiments =>
      {for (final r in store.zoneRecords) r.experiment}.toList()..sort();

  late String _experiment =
      widget.experiment ??
      (store.zoneRecords.isEmpty ? '' : store.zoneRecords.first.experiment);

  static String _f1(double v) => v.isFinite ? v.toStringAsFixed(1) : '–';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final experiments = _experiments;
    if (!experiments.contains(_experiment) && experiments.isNotEmpty) {
      _experiment = experiments.first;
    }
    final records = [
      for (final r in store.zoneRecords)
        if (r.experiment == _experiment) r,
    ];
    final rows = summariseZones(records);
    final organisms = {for (final z in rows) z.organism}.toList();
    final diskMm = records.isEmpty ? 6.0 : records.first.diskMm;
    return Scaffold(
      appBar: AppBar(title: Text(tr.zoneResults)),
      body: ListView(
        padding: scrollPadding(context, const EdgeInsets.all(16)),
        children: [
          DropdownButtonFormField<String>(
            key: ValueKey('exp$_experiment'),
            isExpanded: true,
            initialValue: experiments.contains(_experiment)
                ? _experiment
                : null,
            decoration: InputDecoration(
              labelText: tr.zoneExperiment,
              border: const OutlineInputBorder(),
            ),
            items: [
              for (final e in experiments)
                DropdownMenuItem(
                  value: e,
                  child: Text(
                    e.isEmpty ? tr.zoneNoExperiment : e,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (v) => setState(() => _experiment = v ?? _experiment),
          ),
          const SizedBox(height: 8),
          Text(tr.zoneResultsPlates(records.length), style: t.bodySmall),
          const SizedBox(height: 12),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(tr.zoneResultsNone, textAlign: TextAlign.center),
            ),
          for (final org in organisms) ...[
            Text(
              org.isEmpty ? tr.zoneNoOrganism : org,
              style: t.titleMedium?.copyWith(fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 8),
            _ZoneBars(
              rows: [
                for (final z in rows)
                  if (z.organism == org) z,
              ],
              diskMm: diskMm,
            ),
            const SizedBox(height: 8),
            Table(
              columnWidths: const {
                0: FlexColumnWidth(),
                1: IntrinsicColumnWidth(),
                2: IntrinsicColumnWidth(),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                TableRow(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Theme.of(context).dividerColor),
                    ),
                  ),
                  children: [
                    _cell(tr.zoneColItem, t.labelLarge),
                    _cell('n', t.labelLarge, end: true),
                    _cell(tr.zoneColMean, t.labelLarge, end: true),
                  ],
                ),
                for (final z in rows)
                  if (z.organism == org)
                    TableRow(
                      children: [
                        _cell(z.label, t.bodyMedium),
                        _cell('${z.n}', t.bodyMedium, end: true),
                        _cell(
                          z.n < 2
                              ? _f1(z.mean)
                              : '${_f1(z.mean)} ± ${_f1(z.sd)}',
                          t.bodyMedium,
                          end: true,
                        ),
                      ],
                    ),
              ],
            ),
            const SizedBox(height: 24),
          ],
          Text(tr.zoneResultsNote, style: t.bodySmall),
        ],
      ),
    );
  }

  Widget _cell(String text, TextStyle? style, {bool end = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
    child: Text(
      text,
      style: style,
      textAlign: end ? TextAlign.end : TextAlign.start,
    ),
  );
}

/// One horizontal bar per test item (mean), with a ±SD whisker and a line at
/// the disk size (the smallest a zone can be).
class _ZoneBars extends StatelessWidget {
  const _ZoneBars({required this.rows, required this.diskMm});

  final List<ZoneSummary> rows;
  final double diskMm;

  static const double rowHeight = 28;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Semantics(
      label: rows
          .map((z) => '${z.label} ${z.mean.toStringAsFixed(1)} mm')
          .join(', '),
      child: SizedBox(
        height: rows.length * rowHeight + 20,
        child: CustomPaint(
          size: Size.infinite,
          painter: _BarsPainter(
            rows: rows,
            diskMm: diskMm,
            bar: seriesColour(context, 0),
            ink: cs.onSurface,
            muted: cs.onSurfaceVariant,
            style: t.bodySmall!,
          ),
        ),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.rows,
    required this.diskMm,
    required this.bar,
    required this.ink,
    required this.muted,
    required this.style,
  });

  final List<ZoneSummary> rows;
  final double diskMm;
  final Color bar;
  final Color ink;
  final Color muted;
  final TextStyle style;

  TextPainter _text(String s, Color c, double maxWidth) => TextPainter(
    text: TextSpan(
      text: s,
      style: style.copyWith(
        color: c,
        fontFamily: 'Roboto',
        fontFamilyFallback: const ['ColonySymbols'],
      ),
    ),
    maxLines: 1,
    ellipsis: '…',
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: maxWidth);

  @override
  void paint(Canvas canvas, Size size) {
    const h = _ZoneBars.rowHeight;
    final labelW = math.min(110.0, size.width * 0.3);
    final x0 = labelW + 8;
    final w = size.width - x0 - 8;
    var top = diskMm;
    for (final z in rows) {
      final v = z.mean + (z.sd.isFinite ? z.sd : 0);
      if (v > top) top = v;
    }
    // A round scale end, 5 mm steps.
    final maxMm = (top / 5).ceil() * 5.0 + (top % 5 == 0 ? 5 : 0);
    double xOf(double mm) => x0 + w * mm / maxMm;

    final grid = Paint()
      ..color = muted.withValues(alpha: 0.25)
      ..strokeWidth = 1;
    final bottom = rows.length * h;
    for (var mm = 0.0; mm <= maxMm; mm += 5) {
      canvas.drawLine(Offset(xOf(mm), 0), Offset(xOf(mm), bottom), grid);
      final tp = _text(mm.toStringAsFixed(0), muted, 40);
      tp.paint(canvas, Offset(xOf(mm) - tp.width / 2, bottom + 2));
    }
    // The disk size: a zone can be no smaller.
    canvas.drawLine(
      Offset(xOf(diskMm), 0),
      Offset(xOf(diskMm), bottom),
      Paint()
        ..color = muted
        ..strokeWidth = 1.5,
    );

    for (var i = 0; i < rows.length; i++) {
      final z = rows[i];
      final cy = i * h + h / 2;
      final label = _text(z.label, ink, labelW);
      label.paint(canvas, Offset(labelW - label.width, cy - label.height / 2));
      canvas.drawRect(
        Rect.fromLTRB(x0, cy - h * 0.3, xOf(z.mean), cy + h * 0.3),
        Paint()..color = bar,
      );
      if (z.sd.isFinite && z.sd > 0) {
        final whisker = Paint()
          ..color = ink
          ..strokeWidth = 1.5;
        final a = xOf(math.max(0, z.mean - z.sd)), b = xOf(z.mean + z.sd);
        canvas.drawLine(Offset(a, cy), Offset(b, cy), whisker);
        for (final x in [a, b]) {
          canvas.drawLine(Offset(x, cy - 5), Offset(x, cy + 5), whisker);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.rows != rows ||
      old.diskMm != diskMm ||
      old.bar != bar ||
      old.ink != ink ||
      old.style != style;
}
