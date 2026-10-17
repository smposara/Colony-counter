import 'dart:io';

import 'package:colony_counter/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';
import 'samples_helpers.dart';

/// The form field around [f].
Finder box(Finder f) =>
    find.ancestor(of: f, matching: find.byType(InputDecorator)).first;

void main() {
  chapter('labels', (m) async {
    final temp = Directory.systemTemp.createTempSync('labels');
    addTearDown(() => temp.deleteSync(recursive: true));
    final shared = catchShares(m.tester, temp.path);
    await m.start(
      seed: (store) =>
          store.upsertSample(planFor('Lake-A', dilutions: const [4, 5, 6])),
    );

    // Print the labels.
    await m.tap(find.text(tr.homeSamples));
    await m.tap(find.text('Lake-A'));
    await m.tap(find.byType(PopupMenuButton<String>));
    await snap(m, '1-menu', [(find.text(tr.samplesPrintLabels), Mark.tap)]);
    await m.tap(find.text(tr.samplesPrintLabels));
    await m.settle(until: () => shared.isNotEmpty);
    expect(shared, isNotEmpty, reason: 'label sheet shared');
    final page = await m.tester.runAsync(
      () => pdfPage(shared.first, heightMm: 112),
    );
    if (page != null) {
      await showFile(m, 'labels_Lake-A.pdf', page);
      await snap(m, '2-sheet', [(find.byType(Image), Mark.look)]);
      await m.back();
    }
    await m.back();

    // Scan a label: the app opens that plate.
    await snap(m, '3-scan', [(find.byTooltip(tr.homeScanLabel), Mark.tap)]);
    nextPhoto = labelPhoto('Lake-A', dilutionExp: 5, replicate: 2);
    await m.tap(find.byTooltip(tr.homeScanLabel));
    await m.settle(until: () => find.byType(AlertDialog).evaluate().isNotEmpty);
    await snap(m, '4-found', [
      (find.text('Lake-A · 10⁻⁵ · R2'), Mark.look),
      (find.text(tr.samplesJustOpen), Mark.tap),
      (find.text(tr.samplesPhotograph), Mark.tap),
    ]);
    nextPhoto = fixture('sparse.jpg');
    await m.tap(find.text(tr.samplesPhotograph));
    await m.tap(find.text(tr.reviewSavePlate));
    await snap(m, '5-save', [
      (box(find.text('10⁻⁵')), Mark.look),
      (box(find.text('R2')), Mark.look),
    ]);
    await m.show(find.text(tr.saveSheetSave));
    await m.tap(find.text(tr.saveSheetSave));
    await m.settle();
    // The app opens the sample, with the new plate in its plan.
    await snap(m, '6-done', [(find.textContaining('· R2:').first, Mark.look)]);
    await m.back();

    // A label of a sample not set up yet.
    nextPhoto = labelPhoto('Pond-3', dilutionExp: 4, replicate: 1);
    await m.tap(find.byTooltip(tr.homeScanLabel));
    await m.settle(until: () => find.byType(AlertDialog).evaluate().isNotEmpty);
    await snap(m, '7-unknown', [(find.text(tr.samplesSetUp), Mark.tap)]);
    await m.tap(find.text(tr.samplesSetUp));
    await snap(m, '8-setup', [
      (find.widgetWithText(TextField, tr.setupSampleId), Mark.look),
    ]);
    await m.back();

    // Scan a label while saving a single plate.
    await m.tap(find.text(tr.homePlates));
    nextPhoto = fixture('medium.jpg');
    await m.tap(find.text(tr.homeCountPlate));
    await m.tap(find.text(tr.reviewSavePlate));
    await snap(m, '9-sheet', [(find.byTooltip(tr.saveSheetScan), Mark.tap)]);
    nextPhoto = labelPhoto('Lake-A', dilutionExp: 6, replicate: 1);
    await m.tap(find.byTooltip(tr.saveSheetScan));
    await m.settle(until: () => find.text('Lake-A').evaluate().isNotEmpty);
    ScaffoldMessenger.of(m.context).hideCurrentSnackBar();
    await m.settle();
    await snap(m, '10-filled', [
      (box(find.text('Lake-A')), Mark.look),
      (box(find.text('10⁻⁶')), Mark.look),
      (box(find.text('R1')), Mark.look),
    ]);
  });
}
