import 'package:colony_counter/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';
import 'samples_helpers.dart';

Finder field(String label) => find.widgetWithText(TextField, label);

void main() {
  chapter('samples', (m) async {
    await m.start();
    await snap(m, '1-tab', [(find.text(tr.homeSamples), Mark.tap)]);
    await m.tap(find.text(tr.homeSamples));
    await snap(m, '2-new', [(find.text(tr.homeNewSample), Mark.tap)]);
    await m.tap(find.text(tr.homeNewSample));

    // Name and group the sample.
    await m.enter(field(tr.setupSampleId), 'Lake-A');
    await m.enter(field(tr.setupExperiment), 'Chlorine test');
    await m.enter(field(tr.setupCondition), '1 % NaOCl');
    await m.enter(field(tr.setupTimePoint), '2');
    FocusManager.instance.primaryFocus?.unfocus();
    await toTop(m);
    await snap(m, '3-id', [
      (field(tr.setupSampleId), Mark.type),
      (field(tr.setupExperiment), Mark.type),
      (field(tr.setupCondition), Mark.type),
    ]);

    // Plating and kind of sample.
    await reveal(m, find.text(tr.setupPlating));
    await snap(m, '4-kind', [
      (find.text(tr.setupSpread), Mark.tap),
      (find.text(tr.sampleLiquid), Mark.tap),
    ]);

    // Dilutions, replicates, volume.
    await m.tap(find.text('10⁻⁶'));
    await m.tap(find.text('10⁻⁵').last);
    await m.tap(find.byIcon(Icons.remove));
    await reveal(m, find.text(tr.sampleSolid));
    await snap(m, '5-plan', [
      (find.text(tr.setupTo), Mark.tap),
      (find.byIcon(Icons.remove), Mark.tap),
      (field(tr.setupVolumePerPlate), Mark.type),
    ]);

    // Optional experiment details.
    await m.tap(find.text(tr.setupDetails));
    await m.enter(field(tr.setupStrain), 'E. coli ATCC 25922');
    await m.enter(field(tr.setupIncubation), '48');
    await m.enter(field(tr.setupTemperature), '35');
    await m.enter(field(tr.setupOperator), 'Somchai');
    FocusManager.instance.primaryFocus?.unfocus();
    await m.settle();
    await reveal(m, find.text(tr.setupSave));
    await snap(m, '6-details', [
      (find.text(tr.setupDetails), Mark.tap),
      (field(tr.setupStrain), Mark.type),
      (find.text(tr.setupSave), Mark.tap),
    ]);
    await m.tap(find.text(tr.setupSave));

    // The plate list: photograph the next plate.
    final next = find.text(tr.samplesPhotographSlot('10⁻⁴ · R1'));
    await snap(m, '7-plates', [
      (find.byType(ActionChip).first, Mark.look),
      (next, Mark.tap),
      (find.byTooltip(tr.samplesImportFor('10⁻⁴ · R1')), Mark.tap),
    ]);
    nextPhoto = fixture('medium.jpg');
    await m.tap(next);
    await snap(m, '8-review', [(find.text(tr.reviewSavePlate), Mark.tap)]);
    await m.tap(find.text(tr.reviewSavePlate));
    await m.show(find.text(tr.saveSheetSave));
    await snap(m, '9-sheet', [
      (find.textContaining('CFU/mL').last, Mark.look),
      (find.text(tr.saveSheetSave), Mark.tap),
    ]);
    await m.tap(find.text(tr.saveSheetSave));
    await snap(m, '10-next', [
      (find.byType(ActionChip).first, Mark.look),
      (find.text(tr.samplesPhotographSlot('10⁻⁴ · R2')), Mark.tap),
    ]);

    // The other plates (counted the same way).
    await m.tester.runAsync(() async {
      await seedPlate(m.store, 'Lake-A', 4, 2, 131);
      await seedPlate(m.store, 'Lake-A', 5, 1, 13, fixtureName: 'sparse.jpg');
      await seedPlate(m.store, 'Lake-A', 5, 2, 11, fixtureName: 'sparse.jpg');
    });
    await m.settle();
    await toTop(m);
    await snap(m, '11-result', [
      (find.textContaining('CFU/mL').first, Mark.look),
      (find.textContaining('CV ').first, Mark.look),
      (find.textContaining('log₁₀ CFU/mL').first, Mark.look),
    ]);
    await m.tap(find.text('ISO 7218'));
    await snap(m, '12-rule', [
      (find.text('ISO 7218'), Mark.tap),
      (find.textContaining('CFU/mL').first, Mark.look),
    ]);

    // A second sample with the same settings.
    await m.tap(find.byType(PopupMenuButton<String>));
    await snap(m, '13-menu', [
      (find.text(tr.samplesEditPlan), Mark.tap),
      (find.text(tr.samplesNewLikeThis), Mark.tap),
      (find.text(tr.samplesDeleteSample), Mark.tap),
    ]);
    await m.tap(find.text(tr.samplesNewLikeThis));
    await m.enter(field(tr.setupCondition), m.t('Control', 'ชุดควบคุม'));
    FocusManager.instance.primaryFocus?.unfocus();
    await toTop(m);
    await snap(m, '14-like', [
      (field(tr.setupSampleId), Mark.look),
      (field(tr.setupCondition), Mark.type),
    ]);

    // Solid samples: CFU/g.
    await m.tap(find.text(tr.sampleSolid));
    await reveal(m, find.text(tr.sampleKind));
    await snap(m, '15-solid', [
      (find.text(tr.sampleSolid), Mark.tap),
      (field(tr.sampleWeight), Mark.type),
      (field(tr.diluentVolume), Mark.type),
    ]);
    await m.tap(find.text(tr.sampleLiquid));
    await reveal(m, find.text(tr.setupSave));
    await m.tap(find.text(tr.setupSave));
    await m.back();
    await m.back();

    // Find a sample.
    await m.tester.runAsync(() async {
      await m.store.upsertSample(
        planFor('Lake-B', condition: '1 % NaOCl', timeH: 4),
      );
      await m.store.upsertSample(
        planFor('River-1', experiment: 'Survey', condition: '', timeH: null),
      );
    });
    await m.settle();
    await snap(m, '16-list', [(find.text('Lake-A'), Mark.tap)]);
    await m.enter(find.byType(TextField), 'lake');
    FocusManager.instance.primaryFocus?.unfocus();
    await m.settle();
    await snap(m, '17-search', [(find.byType(TextField), Mark.type)]);
  });
}
