import 'package:colony_counter/core/drop_stats.dart';
import 'package:colony_counter/data/sample_info.dart';
import 'package:colony_counter/l10n/l10n.dart';
import 'package:colony_counter/l10n/labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'drops_helpers.dart';
import 'harness.dart';

/// drops_sectors6x2.jpg: a ring of six drops, two of each of 10⁻⁴…10⁻⁶.
/// Drop 3 (10⁻⁵, one colony) is at (350, 738) in the photo; the plate
/// centre is empty agar.
const _drop1 = Offset(853.9, 710);
const _drop3 = Offset(350.1, 738.1);
const _emptyAgar = Offset(600, 560);
const _moved = Offset(600, 640);
const _dropR = 50.0;

Finder _nav(String label) =>
    find.descendant(of: navBar, matching: find.text(label));

/// The label of a filled button found by [button].
Finder _label(Finder button) =>
    find.descendant(of: button, matching: find.byType(Text));

/// The sample's "Photograph 10⁻⁴ R1" button.
Finder get _photograph =>
    _label(find.byWidgetPredicate((w) => w is FilledButton));

/// The review panel's chip for drop [n] ("3: 10⁻⁵ R1 · 1").
Finder _chip(int n) => find.textContaining(RegExp('^$n: '));

/// The preview of the planned drops in the sample setup.
Finder get _preview => find.byWidgetPredicate(
  (w) =>
      w is CustomPaint &&
      w.painter.runtimeType.toString() == '_DropLayoutPreview',
);

void main() {
  chapter('drops', (m) async {
    await m.start();

    // Plan the sample.
    await m.shot('1-samples', [(_nav(tr.homeSamples), Mark.tap)]);
    await m.tap(_nav(tr.homeSamples));
    await m.shot('2-new', [(find.text(tr.homeNewSample), Mark.tap)]);
    await m.tap(find.text(tr.homeNewSample));
    await showAt(m, find.text(tr.setupDrop));
    await m.shot('3-drop', [(find.text(tr.setupDrop), Mark.tap)]);
    await m.tap(find.text(tr.setupDrop));

    final minus = find.byIcon(Icons.remove).first;
    await m.tap(minus);
    await m.tap(minus);
    await showAt(m, find.text(tr.setupReplicates));
    await m.shot('4-dilutions', [
      (field(find.text(tr.setupFrom).first), Mark.look),
      (field(find.text(tr.setupTo).first), Mark.look),
      (minus, Mark.tap),
    ]);

    await showAt(m, find.text(DropLayout.dilutions.text));
    await m.shot('5-plan', [
      (find.text(DropLayout.replicates.text), Mark.tap),
      (find.text(DropLayout.dilutions.text), Mark.tap),
    ]);
    await m.tap(find.text(DropLayout.dilutions.text));

    await showAt(m, find.text(DropArrangement.sectors.text));
    await m.shot('6-layout', [
      (find.text(DropArrangement.free.text), Mark.tap),
      (find.text(DropArrangement.sectors.text), Mark.tap),
      (find.text(DropArrangement.grid.text), Mark.tap),
    ]);
    await m.tap(find.text(DropArrangement.grid.text));
    await showAt(m, find.text(DropArrangement.grid.text), alignment: 0.05);
    await m.shot('7-rows', [
      (find.text(DropArrangement.grid.text), Mark.tap),
      (field(find.text(tr.setupDropPitch)), Mark.look),
      (_preview, Mark.look),
    ]);

    await m.tap(find.text(DropArrangement.sectors.text));
    final plus = find.descendant(
      of: find.ancestor(
        of: find.text(tr.setupDropsPerDilution),
        matching: find.byType(Row),
      ),
      matching: find.byIcon(Icons.add),
    );
    await m.tap(plus);
    await showAt(m, find.text(tr.setupDropsPerDilution), alignment: 0.1);
    await m.shot('8-ring', [(plus, Mark.tap), (_preview, Mark.look)]);

    await showAt(m, find.text(DropMode.pooled.text), alignment: 0.6);
    await m.shot('9-window', [
      (find.text(tr.setupDropWindow), Mark.look),
      (find.text(DropMode.pooled.text), Mark.tap),
      (find.text(DropMode.first.text), Mark.tap),
    ]);

    await showAt(m, find.text(tr.setupSave));
    await m.shot('10-save', [(find.text(tr.setupSave), Mark.tap)]);
    await m.tap(find.text(tr.setupSave));

    // Photograph and check the drops.
    await m.shot('11-photograph', [(_photograph, Mark.tap)]);
    nextPhoto = fixture('drops_sectors6x2.jpg');
    await m.tap(_photograph);
    await showAt(m, find.text(tr.reviewModeDrops), alignment: 1);
    await m.shot('12-review', [
      (photoSpot(m, _drop1, _dropR * 1.6), Mark.look),
      (find.text(tr.reviewModeDrops), Mark.tap),
    ]);
    await clearSpots(m);
    await m.tap(find.text(tr.reviewModeDrops));

    await m.shot('13-tap-drop', [(photoSpot(m, _drop3, _dropR), Mark.look)]);
    await clearSpots(m);
    await tapPhoto(m, _drop3);
    await m.shot('14-drop', [
      (field(find.text(tr.reviewDilution)), Mark.look),
      (field(find.text(tr.reviewReplicate)), Mark.look),
      (find.text(tr.reviewTntc), Mark.tap),
    ]);
    await m.tap(find.text(tr.reviewLeaveOut));
    await m.shot('15-leave-out', [
      (find.text(tr.reviewLeaveOut), Mark.tap),
      (field(find.text(tr.reviewLeaveOutWhy)), Mark.look),
      (find.text(tr.reviewOk), Mark.tap),
    ]);
    await m.tap(find.text(tr.reviewOk));
    await showAt(m, _chip(3), alignment: 0.1);
    await m.shot('16-left-out', [
      (photoSpot(m, _drop3, _dropR), Mark.look),
      (_chip(3), Mark.look),
    ]);
    await clearSpots(m);

    // Add a drop on empty agar, move it, then delete it.
    await tapPhoto(m, _emptyAgar);
    await showAt(m, _chip(7), alignment: 0.1);
    await m.shot('17-add', [
      (photoSpot(m, _emptyAgar, _dropR), Mark.look),
      (_chip(7), Mark.look),
    ]);
    await clearSpots(m);
    await dragOnPhoto(m, _emptyAgar, _moved);
    await m.shot('18-drag', [(photoSpot(m, _moved, _dropR), Mark.drag)]);
    await clearSpots(m);
    await tapPhoto(m, _moved);
    await m.shot('19-delete', [(find.text(tr.reviewDeleteDrop), Mark.tap)]);
    await m.tap(find.text(tr.reviewDeleteDrop));

    // Ring: the first dilution was put at another drop.
    await m.tap(find.byTooltip(tr.reviewMenuTooltip));
    await m.shot('20-menu', [(find.text(tr.reviewTurnLabels), Mark.tap)]);
    await m.tap(find.text(tr.reviewTurnLabels));
    await showAt(m, _chip(1), alignment: 0);
    await m.shot('21-turned', [
      (find.ancestor(of: _chip(1), matching: find.byType(Wrap)), Mark.look),
      (find.byIcon(Icons.undo), Mark.tap),
    ]);
    await m.tap(find.byTooltip(tr.reviewUndo));

    // The drop table.
    await showAt(m, find.text(tr.dropTableTitle), alignment: 0);
    await m.shot('22-table', [
      (find.textContaining('VMR').first, Mark.look),
      (find.textContaining('CFU/mL').first, Mark.look),
      (find.textContaining('95 %').first, Mark.look),
    ]);

    await m.tap(find.text(tr.reviewSavePlate));
    final save = find.widgetWithText(FilledButton, tr.saveSheetSave);
    await m.show(save);
    await m.shot('23-save', [(_label(save), Mark.tap)]);
    await m.tap(save);
    await m.shot('24-result', [
      (find.textContaining('CFU/mL').first, Mark.look),
      (find.text(tr.dropTableTitle), Mark.look),
    ]);
  });
}
