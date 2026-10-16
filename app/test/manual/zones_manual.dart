import 'package:colony_counter/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';
import 'zones_helpers.dart';

/// The dropdown labelled [label].
Finder dropdown(String label) => find
    .ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate((w) => w is DropdownButtonFormField),
    )
    .first;

void main() {
  chapter('zones', (m) async {
    await m.start();
    final experiment = m.t('Plant extracts', 'สารสกัดสมุนไพร');

    // The Zones tab and the first-time dialogs.
    await snap(m, '1-tab', [(find.text(tr.homeZones), Mark.tap)]);
    await m.tap(find.text(tr.homeZones).last);
    await snap(m, '2-empty', [(find.text(tr.zonesMeasure), Mark.tap)]);
    await m.tap(find.text(tr.zonesMeasure));
    await snap(m, '3-beta', [
      (find.text(tr.zoneDisclaimerTitle), Mark.look),
      (find.text(tr.zoneDisclaimerOk), Mark.tap),
    ]);
    await m.tap(find.text(tr.zoneDisclaimerOk));
    await snap(m, '4-calibrate', [
      (find.text(tr.calLater), Mark.tap),
      (find.text(tr.calNow), Mark.tap),
    ]);
    await m.tap(find.text(tr.calLater));

    // The setup sheet.
    await snap(m, '5-method', [
      (find.byWidgetPredicate((w) => w is SegmentedButton), Mark.look),
      (find.byKey(const ValueKey('zoneSize')), Mark.type),
      (dropdown(tr.reviewPlateType), Mark.tap),
    ]);
    final fields = find.byType(TextField);
    await m.enter(fields.at(1), 'S. aureus ATCC 25923');
    await m.enter(fields.at(2), experiment);
    FocusManager.instance.primaryFocus?.unfocus();
    await m.settle();
    await snap(m, '6-names', [
      (fields.at(1), Mark.type),
      (fields.at(2), Mark.type),
      (find.byIcon(Icons.add), Mark.tap),
    ]);
    await snap(m, '7-labels', [
      (dropdown(tr.zonePanel), Mark.tap),
      (find.byTooltip(tr.zonePanelNew), Mark.tap),
    ]);
    await m.tap(find.byTooltip(tr.zonePanelNew));
    final dialog = find.byType(AlertDialog);
    final boxes = find.descendant(of: dialog, matching: find.byType(TextField));
    await m.enter(boxes.at(0), m.t('Extracts set A', 'ชุดสารสกัด A'));
    await m.enter(boxes.at(1), kZoneLabels.join('\n'));
    FocusManager.instance.primaryFocus?.unfocus();
    await m.settle();
    await snap(m, '8-list', [
      (boxes.at(0), Mark.type),
      (boxes.at(1), Mark.type),
      (find.text(tr.multiDone), Mark.tap),
    ]);
    await m.tap(find.text(tr.multiDone));
    await m.show(find.text(tr.zoneTakePhoto));
    await snap(m, '9-photo', [
      (dropdown(tr.zonePanel), Mark.look),
      (find.text(tr.zoneTakePhoto), Mark.tap),
      (find.text(tr.zoneFromGallery), Mark.tap),
    ]);
    nextPhoto = fixture('zones_reflected.jpg');
    await m.tap(find.text(tr.zoneTakePhoto));

    // Review: check each disk.
    await snap(m, '10-review', [
      (find.byKey(const ValueKey('zonePhoto')), Mark.look),
      (find.byKey(const ValueKey('zoneChip2')), Mark.tap),
      (find.byTooltip(tr.reviewHideMarks), Mark.tap),
    ]);
    await m.tap(find.byKey(const ValueKey('zoneChip2')));
    await snap(m, '11-disk', [
      (find.byKey(const ValueKey('zoneLabel')), Mark.look),
      (find.byTooltip(tr.zoneSmaller), Mark.tap),
      (find.byTooltip(tr.zoneLarger), Mark.tap),
    ]);
    await m.tap(find.byTooltip(tr.zoneLarger));
    await snap(m, '12-flags', [
      (find.text(tr.zoneNoZone), Mark.tap),
      (
        find
            .ancestor(
              of: find.text(tr.zoneFlagColonies),
              matching: find.byType(Row),
            )
            .first,
        Mark.look,
      ),
      (find.text(tr.multiDone), Mark.tap),
    ]);
    await m.tap(find.text(tr.multiDone));

    // Drag a zone's edge.
    final marks = reviewMarks(m.tester);
    final toScreen = photoToScreen(m.tester, 1200);
    final z = marks[4];
    final from = toScreen(z.x - z.radiusPx, z.y);
    await snap(m, '13-drag', [(await spot(m, around(from, 34)), Mark.drag)]);
    // About 1 mm wider: the left edge moves 0.5 mm out.
    final to = toScreen(z.x - z.radiusPx * (1 + 0.5 / z.diameterMm * 2), z.y);
    final g = await m.tester.startGesture(from);
    // Out past the touch slop, then back to the new edge.
    final out = from - const Offset(30, 0);
    for (var i = 1; i <= 10; i++) {
      await g.moveTo(Offset.lerp(from, out, i / 10)!);
      await m.tester.pump();
    }
    for (var i = 1; i <= 10; i++) {
      await g.moveTo(Offset.lerp(out, to, i / 10)!);
      await m.tester.pump();
    }
    await g.up();
    await m.settle();
    await snap(m, '14-undo', [(find.byTooltip(tr.reviewUndo), Mark.tap)]);

    // A disk the app missed: delete one, then add it back by long-press.
    await m.tap(find.byKey(const ValueKey('zoneChip3')));
    await snap(m, '15-delete', [(find.text(tr.homeDelete), Mark.tap)]);
    final missed = reviewMarks(m.tester)[3];
    await m.tap(find.text(tr.homeDelete));
    final at = photoToScreen(m.tester, 1200)(missed.x, missed.y);
    await snap(m, '16-add', [(await spot(m, around(at, 40)), Mark.hold)]);
    await m.tester.longPressAt(at);
    await m.settle(until: () => find.text(tr.zoneAdded).evaluate().isNotEmpty);
    await m.enter(find.byKey(const ValueKey('zoneLabel')), kZoneLabels[3]);
    FocusManager.instance.primaryFocus?.unfocus();
    await m.settle();
    await snap(m, '17-added', [
      (find.byKey(const ValueKey('zoneMm')), Mark.look),
      (find.byKey(const ValueKey('zoneLabel')), Mark.type),
      (find.text(tr.multiDone), Mark.tap),
    ]);
    await m.tap(find.text(tr.multiDone));

    // The plate circle.
    await snap(m, '18-plate', [(find.byTooltip(tr.zoneFixPlate), Mark.tap)]);
    await m.tap(find.byTooltip(tr.zoneFixPlate));
    final pl = reviewPainter(m.tester).plate!;
    final edge = photoToScreen(m.tester, 1200)(pl.cx + pl.radius, pl.cy);
    await snap(m, '19-circle', [
      (await spot(m, around(edge, 34)), Mark.drag),
      (find.byType(Slider), Mark.drag),
      (find.text(tr.zoneMeasureAgain), Mark.tap),
    ]);
    await m.tap(find.byTooltip(tr.zoneFixPlate));

    // Save.
    await snap(m, '20-save', [
      (find.byTooltip(tr.zoneDetails), Mark.tap),
      (find.text(tr.reviewSavePlate), Mark.tap),
    ]);
    await m.tap(find.text(tr.reviewSavePlate));
    await m.settle(until: () => m.store.zoneRecords.isNotEmpty);
    await addReplicates(m, m.store.zoneRecords.single, [2, 3]);
    await snap(m, '21-list', [
      (find.textContaining(tr.zoneRep(1)), Mark.tap),
      (find.byTooltip(tr.zoneResults), Mark.tap),
    ]);

    // Results.
    await m.tap(find.byTooltip(tr.zoneResults));
    await snap(m, '22-results', [
      (dropdown(tr.zoneExperiment), Mark.tap),
      (
        find.byWidgetPredicate(
          (w) =>
              w is Semantics && (w.properties.label ?? '').contains('Amp 10'),
        ),
        Mark.look,
      ),
      (find.byType(Table), Mark.look),
    ]);
    await m.back();

    // Export and share.
    await m.tap(find.byIcon(Icons.more_vert));
    await snap(m, '23-csv', [(find.text(tr.zoneExportCsv), Mark.tap)]);
    await m.back();
    await m.tap(find.textContaining(tr.zoneRep(1)));
    await snap(m, '24-share', [
      (find.byTooltip(tr.reviewShareAnnotated), Mark.tap),
      (find.text(tr.reviewSaveChanges), Mark.tap),
    ]);
  });
}
