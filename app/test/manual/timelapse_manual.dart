import 'dart:typed_data';

import 'package:colony_counter/l10n/l10n.dart';
import 'package:colony_counter/ui/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'colours_helpers.dart';
import 'harness.dart';

/// The same plate after [h] hours: colonies appear at 10, 18 or 30 h and
/// grow from then on.
Uint8List _plateAt(double h) {
  final at = scatter(45, seed: 7, gap: 40);
  return platePhoto([
    for (var i = 0; i < at.length; i++)
      if (h > [10, 18, 30][i < 20 ? 0 : (i < 35 ? 1 : 2)])
        (
          x: at[i].$1,
          y: at[i].$2,
          r: 4 + 0.25 * (h - [10, 18, 30][i < 20 ? 0 : (i < 35 ? 1 : 2)]),
          rgb: kWhite,
        ),
  ], seed: h.round());
}

/// The icon of an app-bar action, so its whole button is outlined.
Finder _icon(String tooltip) =>
    find.descendant(of: find.byTooltip(tooltip), matching: find.byType(Icon));

/// Types [text] and closes the keyboard (the save sheet reads its fields
/// when it rebuilds, as it does when the keyboard closes).
Future<void> _type(Manual m, Finder field, String text) async {
  await m.enter(field, text);
  m.tester.view.viewInsets = const FakeViewPadding(bottom: 1);
  await m.settle();
  m.tester.view.resetViewInsets();
  FocusManager.instance.primaryFocus?.unfocus();
  await m.settle();
}

void main() {
  chapter('timelapse', (m) async {
    await m.start();
    final hours = find.widgetWithText(TextField, tr.saveSheetIncubation);
    final menu = _icon(tr.reviewMenuTooltip);
    final later = find.text(tr.reviewAddLaterPhoto);

    // First photo: save it with the hours since plating.
    nextPhoto = _plateAt(16);
    await m.tap(find.text(tr.homeCountPlate));
    await m.tap(find.text(tr.reviewSavePlate));
    await _type(m, hours, '16');
    await m.shot('1-hours', [(hours, Mark.look)]);
    await m.tap(find.text(tr.saveSheetSave));

    // Open the saved plate; its menu adds a later photo.
    await m.tap(find.byType(RecordTile).first);
    await m.shot('2-open', [(menu, Mark.tap)]);
    await m.tap(menu);
    await m.shot('3-menu', [
      (find.text(tr.reviewShareAnnotated), Mark.tap),
      (later, Mark.tap),
    ]);

    // The later photo: same plate, its hours since plating.
    for (final h in [24, 40]) {
      if (h != 24) {
        await m.tap(menu);
      }
      nextPhoto = _plateAt(h.toDouble());
      await m.tap(later);
      await m.tap(find.text(tr.reviewSavePlate));
      await _type(m, hours, '$h');
      if (h == 24) {
        await m.shot('4-later', [
          (hours, Mark.look),
          (find.text(tr.saveSheetSave), Mark.tap),
        ]);
      }
      await m.tap(find.text(tr.saveSheetSave));
    }

    // Time-lapse view, from any photo of the plate.
    await m.back();
    await m.tap(find.byType(RecordTile).first);
    await m.tap(menu);
    final view = find.text(tr.reviewTimelapse);
    await m.shot('5-open-view', [(view, Mark.tap)]);
    await m.tap(view);

    final card = find.byWidgetPredicate((w) => w is Card).first;
    await m.shot('6-summary', [
      (card, Mark.look),
      (_icon(tr.timelapseShareCsv), Mark.tap),
      (find.text(tr.timelapseAddLater), Mark.tap),
    ]);

    await m.show(find.text(tr.timelapseChartTitle));
    await m.tester.drag(find.byType(ListView), const Offset(0, 40));
    await m.settle();
    await m.shot('7-chart', [
      (
        find.ancestor(
          of: find.text(tr.timelapseChartTitle),
          matching: find.byType(Card),
        ),
        Mark.look,
      ),
      (find.byType(CircleAvatar).first, Mark.tap),
    ]);

    await m.show(find.text(tr.timelapseAppearanceTitle));
    await m.tester.drag(find.byType(ListView), const Offset(0, 40));
    await m.settle();
    await m.shot('8-appeared', [(find.byType(Image).last, Mark.look)]);
  });
}
