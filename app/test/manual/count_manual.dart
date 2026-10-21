import 'package:colony_counter/l10n/l10n.dart';
import 'package:colony_counter/ui/format.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'count_helpers.dart';
import 'harness.dart';

void main() {
  chapter('count', (m) async {
    await m.start();
    final t = m.tester;

    // --- Take the photo ---------------------------------------------------
    await m.shot('1-home', [
      (find.text(tr.homeCountPlate), Mark.tap),
      (tipIcon(tr.homeImportPhoto), Mark.tap),
    ]);
    nextPhoto = fixture('medium.jpg');
    await m.tap(find.text(tr.homeCountPlate));

    // --- The result -------------------------------------------------------
    await m.shot('2-result', [
      (await around(m, countValue, const EdgeInsets.only(top: 14)), Mark.look),
      (await inside(m, find.byType(InteractiveViewer), 20), Mark.look),
    ]);
    await clearPins(m);

    await m.tap(tipIcon(tr.reviewHideMarks));
    await m.shot('3-hide', [(tipIcon(tr.reviewShowMarks), Mark.tap)]);
    await m.tap(tipIcon(tr.reviewShowMarks));

    // --- Sensitivity ------------------------------------------------------
    await m.tap(tipIcon(tr.reviewSensitivity));
    await t.drag(find.byType(Slider), const Offset(40, 0));
    await m.settle();
    await m.shot('4-sensitivity', [
      (tipIcon(tr.reviewSensitivity), Mark.tap),
      (find.byType(Slider), Mark.drag),
      (find.text(tr.reviewRecount), Mark.tap),
    ]);
    await m.tap(find.text(tr.reviewRecount));

    // --- Plate circle -----------------------------------------------------
    await m.tap(find.text(tr.reviewModePlate));
    await m.shot('5-plate', [
      (find.text(tr.reviewModePlate), Mark.tap),
      (await plateCircle(m), Mark.drag),
    ]);
    await clearPins(m);
    await m.shot('6-plate-size', [
      (find.byType(Slider), Mark.drag),
      (find.text(tr.reviewRecountCircle), Mark.tap),
    ]);
    await m.tap(find.text(tr.reviewRecountCircle));

    // --- Zoom -------------------------------------------------------------
    await pinch(m, onPhoto(m, const Offset(510, 380)), 3);
    await m.shot('7-zoom', [
      (find.text(tr.reviewModeZoom), Mark.tap),
      (await inside(m, find.byType(InteractiveViewer), 20), Mark.look),
    ]);

    // --- Edit marks -------------------------------------------------------
    await m.tap(find.text(tr.reviewModeEdit));
    final wrong = onPhoto(m, const Offset(532.0, 300.8));
    await m.shot('8-edit', [
      (find.text(tr.reviewModeEdit), Mark.tap),
      (await pin(m, wrong), Mark.tap),
    ]);
    await clearPins(m);
    await t.tapAt(wrong);
    await m.settle();

    // Put the removed mark back, as if it had been missed.
    final missed = wrong;
    await m.shot('9-add', [
      (await pin(m, missed), Mark.tap),
      (
        await around(
          m,
          find.textContaining(tr.reviewRemoved(1)),
          const EdgeInsets.only(top: 14),
        ),
        Mark.look,
      ),
    ]);
    await clearPins(m);
    await t.tapAt(missed);
    await m.settle();

    final clump = onPhoto(m, const Offset(420.7, 363.1));
    await m.shot('10-clump', [(await pin(m, clump), Mark.hold)]);
    await clearPins(m);
    await t.longPressAt(clump);
    await m.settle();
    await m.tap(find.byIcon(Icons.add));
    await m.shot('11-clump-n', [
      (find.byIcon(Icons.add), Mark.tap),
      (find.text(tr.reviewSet), Mark.tap),
    ]);
    await m.tap(find.text(tr.reviewSet));
    await m.shot('12-undo', [
      (await around(m, countValue, const EdgeInsets.only(top: 14)), Mark.look),
      (tipIcon(tr.reviewUndo), Mark.tap),
      (find.text(tr.reviewSavePlate), Mark.tap),
    ]);
    await clearPins(m);

    // --- Save -------------------------------------------------------------
    await m.tap(find.text(tr.reviewSavePlate));
    await m.enter(field(tr.saveSheetSampleId), 'Milk A');
    await m.tap(find.text(tr.neat));
    await m.tap(find.text(dilutionLabel(4)).last);
    FocusManager.instance.primaryFocus?.unfocus();
    await m.show(find.text(tr.saveSheetTitle));
    await m.shot('13-details', [
      (await around(m, field(tr.saveSheetSampleId), _above), Mark.type),
      (
        await around(m, find.byType(DropdownButtonFormField<int>), _above),
        Mark.tap,
      ),
      (await around(m, field(tr.saveSheetVolume), _above), Mark.type),
    ]);
    await clearPins(m);
    await m.show(find.text(tr.saveSheetIncubation));
    await m.shot('14-options', [
      (find.text(tr.saveSheetSpreader), Mark.tap),
      (find.text(tr.saveSheetTntc), Mark.tap),
      (await around(m, field(tr.saveSheetIncubation), _above), Mark.type),
    ]);
    await clearPins(m);
    await m.show(find.text(tr.saveSheetSave));
    await m.shot('15-save', [
      (await around(m, field(tr.saveSheetNotes), _above), Mark.type),
      (find.byType(Card), Mark.look),
      (find.text(tr.saveSheetSave), Mark.tap),
    ]);
    await clearPins(m);
    await m.tap(find.text(tr.saveSheetSave));

    // --- The Plates list --------------------------------------------------
    await m.shot('16-list', [
      (await exactly(m, find.byType(ListTile)), Mark.tap),
      (
        await around(
          m,
          find
              .descendant(
                of: find.byType(ListTile),
                matching: find.byType(Text),
              )
              .last,
          const EdgeInsets.only(left: 24),
        ),
        Mark.look,
      ),
    ]);
    await clearPins(m);
    // Most of the way across the row, whatever the screen's width.
    final row = find.byType(ListTile);
    await t.drag(row, Offset(-0.6 * t.getSize(row).width, 0));
    await m.settle();
    await m.shot('17-delete', [(find.text(tr.homeDelete), Mark.tap)]);
    await m.tap(find.text(tr.homeCancel));
    await m.tap(find.byType(ListTile));
    await m.tap(tipIcon(tr.reviewMenuTooltip));
    await m.shot('18-menu', [
      (find.text(tr.reviewShareAnnotated), Mark.tap),
      (
        find.textContaining(tr.reviewPlateTypeItem('').split(':').first),
        Mark.tap,
      ),
    ]);
    await m.back();
    await m.shot('19-save-changes', [
      (find.text(tr.reviewSaveChanges), Mark.tap),
    ]);
    await m.back();

    // --- A crowded plate --------------------------------------------------
    // The accuracy check comes every so many plates; here, this one.
    await t.runAsync(() => m.store.setDefaults(accuracyCheckEvery: 2));
    nextPhoto = fixture('dense.jpg');
    await m.tap(find.text(tr.homeCountPlate));
    await m.shot('20-check', [
      (
        banner(find.textContaining(tr.reviewCheckCount('').split('(').first)),
        Mark.look,
      ),
      (banner(find.text(tr.reviewAccuracyCheck)), Mark.look),
    ]);
    await pinch(m, onPhoto(m, const Offset(740, 300)), 3);
    await m.tap(find.text(tr.reviewModeEdit));
    final clump2 = onPhoto(m, const Offset(775, 277));
    await m.shot('21-check-fix', [(await pin(m, clump2), Mark.hold)]);
    await clearPins(m);
    await t.longPressAt(clump2);
    await m.settle();
    await m.tap(find.byIcon(Icons.add));
    await m.tap(find.text(tr.reviewSet));
    await m.tap(find.text(tr.reviewSavePlate));
    await m.show(find.text(tr.saveSheetVerified));
    await m.tap(find.text(tr.saveSheetVerified));
    await m.shot('22-verified', [(find.text(tr.saveSheetVerified), Mark.tap)]);
    await m.tap(find.text(tr.saveSheetSave));
    await m.shot('23-checked', [
      (
        await around(
          m,
          find.byTooltip(tr.homeChecked),
          const EdgeInsets.only(top: 16),
        ),
        Mark.look,
      ),
    ]);
  });
}

/// A text field by its label.
Finder field(String label) => find.widgetWithText(TextField, label);

/// The coloured box around a banner's [text].
Finder banner(Finder text) =>
    find.ancestor(of: text, matching: find.byType(Container)).first;

/// A box around the plate circle (the plate fills the fixture photos at
/// about (500, 500), radius 428 px).
Future<Finder> plateCircle(Manual m) {
  final c = onPhoto(m, const Offset(500, 500));
  final r = (onPhoto(m, const Offset(928, 500)) - c).dx;
  return box(m, Rect.fromCircle(center: c, radius: r));
}

/// Room above a text field for the callout's badge, clear of its label.
const _above = EdgeInsets.only(top: 8);
