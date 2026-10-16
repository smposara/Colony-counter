import 'package:colony_counter/core/classical.dart';
import 'package:colony_counter/core/plate.dart';
import 'package:colony_counter/data/plate_record.dart';
import 'package:colony_counter/data/plate_store.dart';
import 'package:colony_counter/data/sample_info.dart';
import 'package:colony_counter/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

/// A disinfectant time-kill test: two conditions × three time points, three
/// replicate plates each (counts at the dilution that fell in range).
Future<void> _seed(Manual m, PlateStore store) async {
  final exp = m.t('Disinfectant test', 'ทดสอบสารฆ่าเชื้อ');
  final control = m.t('Control', 'ชุดควบคุม');
  final bleach = m.t('Bleach 0.1 %', 'คลอรีน 0.1 %');
  final rows = [
    ('C-0h', control, 0.0, 4, [82, 128, 101]),
    ('C-2h', control, 2.0, 4, [160, 245, 190]),
    ('C-4h', control, 4.0, 5, [31, 52, 40]),
    ('B-0h', bleach, 0.0, 4, [118, 75, 96]),
    ('B-2h', bleach, 2.0, 2, [150, 64, 102]),
    ('B-4h', bleach, 4.0, 0, [230, 90, 150]),
  ];
  var n = 0;
  for (final (id, cond, t, d, counts) in rows) {
    final at = DateTime(2026, 10, 14, 9 + t.toInt(), n);
    await store.upsertSample(
      SampleInfo(
        sampleId: id,
        experiment: exp,
        condition: cond,
        timeH: t,
        dilutions: [d],
        replicates: 3,
        createdAt: at,
      ),
    );
    for (var r = 0; r < counts.length; r++) {
      n++;
      await store.upsert(
        PlateRecord(
          id: 'cmp$n',
          createdAt: at.add(Duration(minutes: r)),
          imagePath: 'cmp$n.jpg',
          imageWidth: 1000,
          imageHeight: 1000,
          plate: const Plate(500, 500, 440),
          colonies: [
            for (var i = 0; i < counts[r]; i++) Colony(100 + i * 3.0, 500, 5),
          ],
          autoCount: counts[r],
          sampleId: id,
          dilutionExp: d,
          replicate: r + 1,
        ),
      );
    }
  }
}

/// The time-kill chart (a CustomPaint inside an AspectRatio).
final _chart = find.descendant(
  of: find.byType(AspectRatio),
  matching: find.byType(CustomPaint),
);

void main() {
  chapter('compare', (m) async {
    await m.start(seed: (store) => _seed(m, store));

    // Give samples one Experiment name, a Condition and a Time point.
    await m.tap(find.text(tr.homeSamples));
    await m.tap(find.text(tr.homeNewSample));
    final exp = find.widgetWithText(TextField, tr.setupExperiment);
    final cond = find.widgetWithText(TextField, tr.setupCondition);
    final time = find.widgetWithText(TextField, tr.setupTimePoint);
    await m.enter(find.byType(TextField).first, 'B-8h');
    await m.enter(exp, m.t('Disinfectant test', 'ทดสอบสารฆ่าเชื้อ'));
    await m.enter(cond, m.t('Bleach 0.1 %', 'คลอรีน 0.1 %'));
    await m.enter(time, '4');
    await m.tester.testTextInput.receiveAction(TextInputAction.done);
    FocusManager.instance.primaryFocus?.unfocus();
    await m.settle();
    await m.tester.drag(find.byType(ListView), const Offset(0, 600));
    await m.settle();
    await m.shot('1-setup', [
      (exp, Mark.look),
      (cond, Mark.look),
      (time, Mark.look),
    ]);
    await m.back();

    // The Compare tab.
    await m.shot('2-tab', [(find.text(tr.homeCompare).last, Mark.tap)]);
    await m.tap(find.text(tr.homeCompare).last);
    final dropdowns = find.byType(DropdownButtonFormField<String>);
    await m.shot('3-chart', [
      (dropdowns.first, Mark.look),
      (_chart, Mark.look),
    ]);

    // Choose the control.
    await m.tap(dropdowns.last);
    await m.shot('4-control', [
      (find.text(m.t('Control', 'ชุดควบคุม')).last, Mark.tap),
    ]);
    await m.tap(find.text(m.t('Control', 'ชุดควบคุม')).last);

    // Tap a point for its value.
    final box = m.tester.getRect(_chart);
    final x = box.right - 12; // the last time point
    for (var y = box.top + 8; y < box.bottom - 24; y += 12) {
      await m.tester.tapAt(Offset(x, y));
      await m.tester.pump();
      if (find.textContaining(': log₁₀ ').evaluate().isNotEmpty) break;
    }
    await m.settle();
    final value = find.textContaining(': log₁₀ ');
    await m.shot('5-point', [(value, Mark.look)]);

    // Results table, then reduction vs the control.
    final tables = find.byType(DataTable);
    await m.show(find.text(tr.compareResults));
    await m.tester.drag(find.byType(ListView), const Offset(0, 60));
    await m.settle();
    await m.shot('6-results', [(tables.first, Mark.look)]);

    // Reduction vs the control, swiped to its last columns.
    await m.show(find.textContaining(tr.compareReductionVs('')));
    await m.tester.drag(
      find.byWidget(tables.evaluate().last.widget),
      const Offset(-400, 0),
      warnIfMissed: false,
    );
    await m.settle();
    Finder cell(Finder text) => find
        .ancestor(
          of: text,
          matching: find.byWidgetPredicate(
            (w) => w is Container && w.padding != null,
          ),
        )
        .first;
    await m.shot('7-reduction', [
      (cell(find.textContaining('4.4')), Mark.look),
      (cell(find.textContaining('99.99')), Mark.look),
    ]);
  });
}
