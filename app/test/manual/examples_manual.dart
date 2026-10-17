import 'package:colony_counter/data/examples.dart';
import 'package:colony_counter/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  chapter('examples', (m) async {
    // What a new user sees on first launch: the bundled example data.
    await m.start(seed: addExamples);
    await m.shot('1-plates', [
      (find.text(tr.examplesBanner), Mark.look),
      (find.text(tr.examplesBadge).first, Mark.look),
    ]);

    await m.tap(find.text(tr.homeSamples));
    await m.shot('2-samples', [(find.text('Example – lake water'), Mark.tap)]);
    await m.tap(find.text('Example – lake water'));
    await m.shot('3-result', [
      (find.textContaining('CFU/mL').first, Mark.look),
      (find.textContaining(tr.samplesPhotograph).last, Mark.tap),
    ]);
    await m.back();

    await m.tap(find.text(tr.homeCompare));
    await m.shot('4-compare', [
      (
        find.byWidgetPredicate(
          (w) =>
              w is CustomPaint &&
              w.painter.runtimeType.toString() == '_ChartPainter',
        ),
        Mark.look,
      ),
    ]);

    await m.tap(find.text(tr.homeZones));
    await m.shot('5-zones', [(find.text(tr.examplesBadge).first, Mark.look)]);

    // Done exploring: one tap removes them; your own data stays.
    await m.tap(find.text(tr.homePlates));
    await m.shot('6-remove', [(find.text(tr.examplesRemove), Mark.tap)]);
    await m.tap(find.text(tr.examplesRemove));
    await m.shot('7-confirm', [(find.text(tr.examplesRemoveAction), Mark.tap)]);
    await m.tap(find.text(tr.examplesRemoveAction));
    await m.shot('8-empty');
  });
}
