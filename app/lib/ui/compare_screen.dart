import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/stats.dart';
import '../data/plate_store.dart';
import '../data/sample_info.dart';
import 'chart_colours.dart';
import 'format.dart';
import 'samples_screen.dart';

/// One cell of the comparison: a condition at a time point.
class _Cell {
  _Cell(this.samples, this.stats);

  final List<SampleInfo> samples;
  final ReplicateStats stats;
}

/// Compares conditions within an experiment: log₁₀ CFU/mL ± SD per condition
/// and time point, log reduction vs a control, and a time-course chart.
class CompareTab extends StatefulWidget {
  const CompareTab({super.key, required this.store});

  final PlateStore store;

  @override
  State<CompareTab> createState() => _CompareTabState();
}

class _CompareTabState extends State<CompareTab> {
  String? _experiment;
  String? _control;

  PlateStore get store => widget.store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final experiments = store.experiments();
        if (experiments.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'Give samples the same Experiment name and a Condition '
                '(e.g. Control / Treated), and optionally a time point, to compare '
                'them here: log reduction, % kill, and time-kill or growth curves.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        final exp = experiments.contains(_experiment)
            ? _experiment!
            : experiments.first;
        final samples = store
            .allSamples()
            .where((s) => s.experiment == exp)
            .toList();

        // Group replicates of the same condition and time point together.
        final conditions = <String>[];
        final times = <double?>{};
        final cells = <(String, double?), _Cell>{};
        final byKey = <(String, double?), List<SampleInfo>>{};
        for (final s in samples) {
          final cond = s.condition.isEmpty ? s.sampleId : s.condition;
          if (!conditions.contains(cond)) conditions.add(cond);
          times.add(s.timeH);
          (byKey[(cond, s.timeH)] ??= []).add(s);
        }
        conditions.sort(
          (a, b) => _isControl(a) == _isControl(b)
              ? a.compareTo(b)
              : (_isControl(a) ? -1 : 1),
        );
        for (final e in byKey.entries) {
          // All replicate values of all samples in this cell.
          final values = <double>[
            for (final s in e.value)
              ...s.analyse(store.platesOf(s.sampleId), store.rule).stats.values,
          ];
          cells[e.key] = _Cell(e.value, ReplicateStats(values));
        }
        final timeList = times.toList()
          ..sort((a, b) => (a ?? -1).compareTo(b ?? -1));
        final control = conditions.contains(_control)
            ? _control!
            : conditions.firstWhere(_isControl, orElse: () => conditions.first);

        final t = Theme.of(context).textTheme;
        final dark = Theme.of(context).brightness == Brightness.dark;
        final palette = dark ? seriesDark : seriesLight;
        Color colourOf(String cond) =>
            palette[conditions.indexOf(cond) % palette.length];
        final numericTimes = timeList.whereType<double>().toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            DropdownButtonFormField<String>(
              key: ValueKey(exp),
              initialValue: exp,
              decoration: const InputDecoration(
                labelText: 'Experiment',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final e in experiments)
                  DropdownMenuItem(value: e, child: Text(e)),
              ],
              onChanged: (v) => setState(() {
                _experiment = v;
                _control = null;
              }),
            ),
            const SizedBox(height: 12),
            if (conditions.length > 1)
              DropdownButtonFormField<String>(
                key: ValueKey('$exp/$control'),
                initialValue: control,
                decoration: const InputDecoration(
                  labelText: 'Control',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final c in conditions)
                    DropdownMenuItem(value: c, child: Text(c)),
                ],
                onChanged: (v) => setState(() => _control = v),
              ),
            if (numericTimes.length > 1) ...[
              const SizedBox(height: 20),
              Text('log₁₀ CFU/mL over time', style: t.titleMedium),
              Text(
                'Mean ± SD of replicates; tap a point for its value.',
                style: t.bodySmall,
              ),
              const SizedBox(height: 8),
              _TimeChart(
                series: [
                  for (final c in conditions)
                    _Series(c, colourOf(c), [
                      for (final time in numericTimes)
                        if (cells[(c, time)] case final cell?
                            when cell.stats.n > 0)
                          (
                            time,
                            cell.stats.log10Mean,
                            cell.stats.n > 1 ? cell.stats.log10Sd : 0.0,
                            cell.stats.n,
                          ),
                    ]),
                ],
              ),
            ],
            const SizedBox(height: 20),
            Text('Results', style: t.titleMedium),
            const SizedBox(height: 4),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 20,
                headingRowHeight: 40,
                columns: [
                  const DataColumn(label: Text('Condition')),
                  for (final time in timeList)
                    DataColumn(
                      label: Text(
                        time == null ? 'log₁₀ CFU/mL' : hoursLabel(time),
                      ),
                    ),
                ],
                rows: [
                  for (final c in conditions)
                    DataRow(
                      cells: [
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (numericTimes.length > 1) ...[
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: colourOf(c),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                              ],
                              Text(c),
                            ],
                          ),
                        ),
                        for (final time in timeList)
                          DataCell(Text(_cellText(cells[(c, time)]))),
                      ],
                    ),
                ],
              ),
            ),
            if (conditions.length > 1) ...[
              const SizedBox(height: 20),
              Text('Reduction vs $control', style: t.titleMedium),
              Text(
                'log reduction = mean log₁₀(control) − mean log₁₀(treated); '
                'SD combines both groups. % kill from the geometric means.',
                style: t.bodySmall,
              ),
              const SizedBox(height: 4),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 20,
                  headingRowHeight: 40,
                  columns: const [
                    DataColumn(label: Text('Condition')),
                    DataColumn(label: Text('Time')),
                    DataColumn(label: Text('log reduction')),
                    DataColumn(label: Text('% kill')),
                  ],
                  rows: [
                    for (final c in conditions.where((c) => c != control))
                      for (final time in timeList)
                        if (_reduction(cells, control, c, time) case final r?)
                          DataRow(
                            cells: [
                              DataCell(Text(c)),
                              DataCell(
                                Text(time == null ? '—' : hoursLabel(time)),
                              ),
                              DataCell(
                                Text(
                                  '${fixed(r.logReduction)}'
                                  '${r.control.n > 1 || r.treated.n > 1 ? ' ± ${fixed(r.logReductionSd)}' : ''}',
                                ),
                              ),
                              DataCell(Text(_percent(r.percentKill))),
                            ],
                          ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            Text('Samples', style: t.titleMedium),
            for (final s in samples)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(s.sampleId),
                subtitle: Text(
                  [
                    if (s.condition.isNotEmpty) s.condition,
                    if (s.timeH != null) hoursLabel(s.timeH!),
                    resultSummary(
                      s.analyse(store.platesOf(s.sampleId), store.rule),
                    ),
                  ].join(' · '),
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        SampleDetailScreen(store: store, sampleId: s.sampleId),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  static bool _isControl(String c) {
    final l = c.toLowerCase();
    return l.contains('control') ||
        l.contains('ctrl') ||
        l.contains('untreated');
  }

  /// Treated vs control at the same time point (or the control's only time
  /// point when the control has a single one, e.g. t = 0).
  static Reduction? _reduction(
    Map<(String, double?), _Cell> cells,
    String control,
    String cond,
    double? time,
  ) {
    final treated = cells[(cond, time)];
    if (treated == null || treated.stats.n == 0) return null;
    var ctrl = cells[(control, time)];
    if (ctrl == null) {
      final controlCells = cells.entries
          .where((e) => e.key.$1 == control)
          .toList();
      if (controlCells.length == 1) ctrl = controlCells.single.value;
    }
    if (ctrl == null || ctrl.stats.n == 0) return null;
    return Reduction(ctrl.stats, treated.stats);
  }

  static String _cellText(_Cell? c) {
    if (c == null || c.stats.n == 0) return '—';
    final s = c.stats;
    return '${fixed(s.log10Mean)}${s.n > 1 ? ' ± ${fixed(s.log10Sd)}' : ''} (n=${s.n})';
  }

  static String _percent(double p) {
    if (!p.isFinite) return '—';
    if (p >= 99.99) return '${p.toStringAsFixed(4)} %';
    if (p >= 99) return '${p.toStringAsFixed(2)} %';
    return '${p.toStringAsFixed(1)} %';
  }
}

class _Series {
  _Series(this.name, this.colour, this.points);

  final String name;
  final Color colour;

  /// (time h, log10 mean, log10 SD, n)
  final List<(double, double, double, int)> points;
}

class _TimeChart extends StatefulWidget {
  const _TimeChart({required this.series});

  final List<_Series> series;

  @override
  State<_TimeChart> createState() => _TimeChartState();
}

class _TimeChartState extends State<_TimeChart> {
  (int, int)? _selected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final series = widget.series.where((s) => s.points.isNotEmpty).toList();
    if (series.isEmpty) return const SizedBox.shrink();
    final sel = _selected;
    final selPoint =
        sel != null &&
            sel.$1 < series.length &&
            sel.$2 < series[sel.$1].points.length
        ? series[sel.$1].points[sel.$2]
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Legend: always shown for 2+ series so identity is not colour-only.
        if (series.length > 1)
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              for (final s in series)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 16, height: 3, color: s.colour),
                    const SizedBox(width: 6),
                    Text(s.name, style: t.bodySmall),
                  ],
                ),
            ],
          ),
        const SizedBox(height: 8),
        AspectRatio(
          aspectRatio: 1.5,
          child: LayoutBuilder(
            builder: (context, box) {
              final painter = _ChartPainter(
                series: series,
                ink: cs.onSurfaceVariant,
                grid: cs.outlineVariant.withValues(alpha: 0.5),
                surface: cs.surface,
                selected: sel,
                labelStyle: t.labelSmall!.copyWith(color: cs.onSurfaceVariant),
              );
              return GestureDetector(
                onTapUp: (d) => setState(
                  () => _selected = painter.hit(d.localPosition, box.biggest),
                ),
                child: CustomPaint(size: box.biggest, painter: painter),
              );
            },
          ),
        ),
        SizedBox(
          height: 20,
          child: selPoint == null
              ? null
              : Text(
                  '${series[sel!.$1].name} · ${hoursLabel(selPoint.$1)}: log₁₀ ${fixed(selPoint.$2)}'
                  '${selPoint.$4 > 1 ? ' ± ${fixed(selPoint.$3)}' : ''} (n=${selPoint.$4})',
                  style: t.bodySmall,
                ),
        ),
      ],
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.series,
    required this.ink,
    required this.grid,
    required this.surface,
    required this.selected,
    required this.labelStyle,
  });

  final List<_Series> series;
  final Color ink;
  final Color grid;
  final Color surface;
  final (int, int)? selected;
  final TextStyle labelStyle;

  static const _left = 36.0, _bottom = 24.0, _top = 8.0, _right = 12.0;

  late double _x0, _x1, _y0, _y1;

  void _bounds() {
    final xs = [
      for (final s in series)
        for (final p in s.points) p.$1,
    ];
    final lo = [
      for (final s in series)
        for (final p in s.points) p.$2 - p.$3,
    ];
    final hi = [
      for (final s in series)
        for (final p in s.points) p.$2 + p.$3,
    ];
    _x0 = 0;
    _x1 = math.max(1, xs.reduce(math.max));
    _y0 = (lo.reduce(math.min) - 0.5).floorToDouble();
    _y1 = (hi.reduce(math.max) + 0.5).ceilToDouble();
    if (_y1 - _y0 < 2) _y1 = _y0 + 2;
  }

  Offset _pos(Size size, double x, double y) => Offset(
    _left + (x - _x0) / (_x1 - _x0) * (size.width - _left - _right),
    _top + (1 - (y - _y0) / (_y1 - _y0)) * (size.height - _top - _bottom),
  );

  (int, int)? hit(Offset tap, Size size) {
    _bounds();
    (int, int)? best;
    var bestD = 28.0; // generous touch target
    for (var i = 0; i < series.length; i++) {
      for (var j = 0; j < series[i].points.length; j++) {
        final p = series[i].points[j];
        final d = (_pos(size, p.$1, p.$2) - tap).distance;
        if (d < bestD) {
          bestD = d;
          best = (i, j);
        }
      }
    }
    return best;
  }

  void _label(
    Canvas c,
    String text,
    Offset at, {
    bool right = false,
    bool centre = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = right ? -tp.width : (centre ? -tp.width / 2 : 0.0);
    tp.paint(c, at + Offset(dx, -tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    _bounds();
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    // Horizontal grid at whole log units, recessive.
    for (var y = _y0; y <= _y1 + 1e-9; y += 1) {
      final a = _pos(size, _x0, y), b = _pos(size, _x1, y);
      canvas.drawLine(a, b, gridPaint);
      _label(canvas, y.toStringAsFixed(0), a - const Offset(6, 0), right: true);
    }
    // Time ticks at each sampled time point.
    final times = {
      for (final s in series)
        for (final p in s.points) p.$1,
    }.toList()..sort();
    for (final x in times) {
      final p = _pos(size, x, _y0);
      _label(
        canvas,
        '${fixed(x, x % 1 == 0 ? 0 : 1)} h',
        p + const Offset(0, 12),
        centre: true,
      );
    }
    canvas.drawLine(
      _pos(size, _x0, _y0),
      _pos(size, _x1, _y0),
      Paint()
        ..color = ink
        ..strokeWidth = 1,
    );

    for (var i = 0; i < series.length; i++) {
      final s = series[i];
      final line = Paint()
        ..color = s.colour
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final pts = [for (final p in s.points) _pos(size, p.$1, p.$2)];
      if (pts.length > 1) {
        canvas.drawPath(Path()..addPolygon(pts, false), line);
      }
      for (var j = 0; j < s.points.length; j++) {
        final p = s.points[j];
        if (p.$3 > 0) {
          final a = _pos(size, p.$1, p.$2 - p.$3),
              b = _pos(size, p.$1, p.$2 + p.$3);
          final bar = Paint()
            ..color = s.colour
            ..strokeWidth = 1.5;
          canvas.drawLine(a, b, bar);
          canvas.drawLine(a - const Offset(4, 0), a + const Offset(4, 0), bar);
          canvas.drawLine(b - const Offset(4, 0), b + const Offset(4, 0), bar);
        }
        final sel = selected == (i, j);
        // Surface ring keeps overlapping markers distinct.
        canvas.drawCircle(pts[j], sel ? 7 : 5.5, Paint()..color = surface);
        canvas.drawCircle(pts[j], sel ? 6 : 4, Paint()..color = s.colour);
      }
    }
  }

  @override
  bool shouldRepaint(_ChartPainter old) => true;
}
