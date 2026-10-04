import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/accuracy.dart';
import '../data/plate_store.dart';
import 'chart_colours.dart';
import 'format.dart';
import 'review_screen.dart';

/// How well the automatic count does on the user's own plates, from plates
/// whose every colony was checked by hand.
class AccuracyScreen extends StatelessWidget {
  const AccuracyScreen({super.key, required this.store});

  final PlateStore store;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Counting accuracy')),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final report = AccuracyReport(store.records);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              if (report.points.isEmpty)
                const _HowTo()
              else ...[
                _Summary(report.all),
                const SizedBox(height: 16),
                _ScatterCard(report: report),
                const SizedBox(height: 16),
                _BreakdownCard(report: report),
                const SizedBox(height: 16),
                _PlateList(store: store, report: report),
              ],
              const SizedBox(height: 16),
              _Frequency(store: store),
            ],
          );
        },
      ),
    );
  }
}

String _pct(double v, {bool signed = false}) =>
    v.isNaN ? '—' : '${signed && v > 0 ? '+' : ''}${v.toStringAsFixed(1)} %';

class _HowTo extends StatelessWidget {
  const _HowTo();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('No checked plates yet', style: t.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Now and then, check every colony on a plate: zoom in, remove '
              'wrong marks, add missed colonies, and set clusters. Then turn on '
              '"Checked every colony" when saving. The app compares its own '
              'count with yours and shows here how accurate it is on your '
              'plates.',
              style: t.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary(this.s);

  final CountErrors s;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget stat(String label, String value) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: t.titleLarge),
          Text(label, style: t.bodySmall),
        ],
      ),
    );
    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.within10Percent.isNaN
                  ? '${s.n} checked plate${s.n == 1 ? '' : 's'}'
                  : '${s.within10Percent.toStringAsFixed(0)} % of plates within ±10 %',
              style: t.headlineSmall,
            ),
            Text(
              'of the checked count · ${s.n} checked plate${s.n == 1 ? '' : 's'}',
              style: t.bodyMedium,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                stat('mean error', _pct(s.meanAbsPercent)),
                stat('bias', _pct(s.biasPercent, signed: true)),
                stat('colonies off, on average', fixed(s.meanAbsError, 1)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                stat('of marks were colonies', _pct(s.precision)),
                stat('of colonies found', _pct(s.recall)),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Percentages use plates with 10 or more colonies. Negative bias '
              'means the app counts too few.',
              style: t.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Automatic vs checked count, one dot per plate, against the line of
/// perfect agreement and a ±10 % band.
class _ScatterCard extends StatefulWidget {
  const _ScatterCard({required this.report});

  final AccuracyReport report;

  @override
  State<_ScatterCard> createState() => _ScatterCardState();
}

class _ScatterCardState extends State<_ScatterCard> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final pts = widget.report.points;
    final colours = [seriesColour(context, 0), seriesColour(context, 1)];
    final painter = _ScatterPainter(
      points: pts,
      colours: colours,
      ink: cs.onSurfaceVariant,
      grid: cs.outlineVariant.withValues(alpha: 0.5),
      band: cs.surfaceContainerHighest,
      surface: cs.surfaceContainerLow,
      selected: _selected,
      labelStyle: t.labelSmall!.copyWith(color: cs.onSurfaceVariant),
    );
    final sel = _selected == null ? null : pts[_selected!];
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Automatic vs checked count', style: t.titleMedium),
            const SizedBox(height: 4),
            Wrap(
              spacing: 16,
              children: [
                for (final (i, label) in const [
                  (0, 'Not flagged'),
                  (1, 'Flagged for checking'),
                ])
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: colours[i],
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(label, style: t.bodySmall),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 8),
            AspectRatio(
              aspectRatio: 1.2,
              child: LayoutBuilder(
                builder: (context, box) => GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) => setState(
                    () => _selected = painter.hit(d.localPosition, box.biggest),
                  ),
                  child: CustomPaint(painter: painter, size: box.biggest),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              sel == null
                  ? 'Tap a dot for details. Dots below the line: the app '
                        'counted too few. Shaded: within ±10 %.'
                  : '${plateLabel(sel.record)} · ${shortDate(sel.record.createdAt)}: '
                        'app ${sel.auto}, checked ${sel.checked}'
                        '${sel.errorPercent == null ? '' : ' (${_pct(sel.errorPercent!, signed: true)})'}',
              style: t.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ScatterPainter extends CustomPainter {
  _ScatterPainter({
    required this.points,
    required this.colours,
    required this.ink,
    required this.grid,
    required this.band,
    required this.surface,
    required this.selected,
    required this.labelStyle,
  });

  final List<AccuracyPoint> points;
  final List<Color> colours;
  final Color ink, grid, band, surface;
  final int? selected;
  final TextStyle labelStyle;

  static const _left = 36.0, _bottom = 28.0, _top = 8.0, _right = 8.0;

  double get _max {
    final m = points.fold(
      10,
      (a, p) => math.max(a, math.max(p.auto, p.checked)),
    );
    return _niceCeil(m * 1.05);
  }

  static double _niceCeil(double v) {
    final e = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
    for (final m in const [1, 2, 2.5, 5, 10]) {
      if (m * e >= v) return m * e;
    }
    return 10 * e;
  }

  Offset _pos(Size s, double checked, double auto) {
    final m = _max;
    return Offset(
      _left + checked / m * (s.width - _left - _right),
      _top + (1 - auto / m) * (s.height - _top - _bottom),
    );
  }

  int? hit(Offset tap, Size size) {
    int? best;
    var bestD = 24.0;
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final d =
          (_pos(size, p.checked.toDouble(), p.auto.toDouble()) - tap).distance;
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }

  void _text(Canvas c, String s, Offset at, {bool right = false}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, at + Offset(right ? -tp.width : -tp.width / 2, -tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final m = _max;
    // ±10 % band around perfect agreement.
    canvas.drawPath(
      Path()..addPolygon([
        _pos(size, 0, 0),
        _pos(size, m, m * 0.9),
        _pos(size, m / 1.1, m),
      ], true),
      Paint()..color = band,
    );
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var k = 0; k <= 4; k++) {
      final v = m * k / 4;
      canvas.drawLine(_pos(size, 0, v), _pos(size, m, v), gridPaint);
      _text(
        canvas,
        v.toStringAsFixed(0),
        _pos(size, 0, v) - const Offset(6, 0),
        right: true,
      );
      _text(
        canvas,
        v.toStringAsFixed(0),
        _pos(size, v, 0) + const Offset(0, 10),
      );
    }
    _text(canvas, 'checked count →', Offset(size.width - 50, size.height - 6));
    canvas.drawLine(
      _pos(size, 0, 0),
      _pos(size, m, m),
      Paint()
        ..color = ink
        ..strokeWidth = 1,
    );
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final at = _pos(size, p.checked.toDouble(), p.auto.toDouble());
      final sel = i == selected;
      canvas.drawCircle(at, sel ? 7 : 5.5, Paint()..color = surface);
      canvas.drawCircle(
        at,
        sel ? 6 : 4,
        Paint()..color = colours[p.warned ? 1 : 0],
      );
    }
  }

  @override
  bool shouldRepaint(_ScatterPainter old) => true;
}

class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({required this.report});

  final AccuracyReport report;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final (warned, rest) = report.byWarning;
    final rows = [
      for (final e in report.byRange.entries) ('${e.key} colonies', e.value),
      ('Flagged for checking', warned),
      ('Not flagged', rest),
    ];
    TableRow row(List<String> cells, {bool head = false}) => TableRow(
      children: [
        for (final (i, c) in cells.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              c,
              textAlign: i == 0 ? TextAlign.start : TextAlign.end,
              style: head ? t.labelMedium : t.bodyMedium,
            ),
          ),
      ],
    );
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Where the errors are', style: t.titleMedium),
            const SizedBox(height: 4),
            Table(
              columnWidths: const {0: FlexColumnWidth(2.2)},
              children: [
                row(['', 'plates', 'mean error', 'bias'], head: true),
                for (final (label, s) in rows)
                  row([
                    label,
                    '${s.n}',
                    _pct(s.meanAbsPercent),
                    _pct(s.biasPercent, signed: true),
                  ]),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'If the warnings are useful, flagged plates have the larger errors.',
              style: t.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _PlateList extends StatelessWidget {
  const _PlateList({required this.store, required this.report});

  final PlateStore store;
  final AccuracyReport report;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Checked plates', style: t.titleMedium),
        for (final p in report.points)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(plateLabel(p.record)),
            subtitle: Text(shortDate(p.record.createdAt)),
            trailing: Text(
              'app ${p.auto} · checked ${p.checked}'
              '${p.errorPercent == null ? '' : '\n${_pct(p.errorPercent!, signed: true)}'}',
              textAlign: TextAlign.end,
              style: t.bodySmall,
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ReviewScreen(store: store, record: p.record),
              ),
            ),
          ),
      ],
    );
  }
}

class _Frequency extends StatelessWidget {
  const _Frequency({required this.store});

  final PlateStore store;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Ask me to check a plate', style: t.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 0, label: Text('Never')),
            ButtonSegment(value: 10, label: Text('Every 10th')),
            ButtonSegment(value: 20, label: Text('Every 20th')),
            ButtonSegment(value: 50, label: Text('Every 50th')),
          ],
          selected: {store.accuracyCheckEvery},
          onSelectionChanged: (s) =>
              store.setDefaults(accuracyCheckEvery: s.first),
        ),
        const SizedBox(height: 4),
        Text(
          'The review screen then asks you to check every colony on that '
          'plate before saving.',
          style: t.bodySmall,
        ),
      ],
    );
  }
}
