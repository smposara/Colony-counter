import 'package:colony_counter/core/plate.dart';
import 'package:colony_counter/data/sample_info.dart';
import 'package:colony_counter/l10n/l10n.dart';
import 'package:colony_counter/l10n/labels.dart';
import 'package:colony_counter/ui/review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'drops_helpers.dart';
import 'harness.dart';

// Colonies in the film photos (image pixels, from their .json files).
/// film_ec.jpg: a red colony with gas (a coliform).
const _ecRedGas = Offset(626.6, 491.2);

/// film_ec.jpg: a blue colony without gas (not counted).
const _ecBlueNoGas = Offset(631.2, 377.9);

/// film_eb.jpg: a red colony without gas or yellow zone (not counted).
const _ebRed = Offset(679.3, 729.2);
const _colonyR = 75.0;

Finder _nav(String label) =>
    find.descendant(of: navBar, matching: find.text(label));

Finder _label(Finder button) =>
    find.descendant(of: button, matching: find.byType(Text));

/// The sample's "Photograph 10⁻¹ R1" button.
Finder get _photograph =>
    _label(find.byWidgetPredicate((w) => w is FilledButton));

SampleInfo _film(String id, PlateFormat format) => SampleInfo(
  sampleId: id,
  method: PlatingMethod.film,
  format: format,
  dilutions: const [1],
  replicates: 1,
  volumeMl: 1,
);

/// Opens sample [id] from the Samples list and photographs [photo].
Future<void> _photographSample(Manual m, String id, String photo) async {
  await m.tester.runAsync(
    () => m.store.upsertSample(
      _film(id, id == 'EB1' ? PlateFormat.filmEb : PlateFormat.filmAc),
    ),
  );
  await m.settle();
  await m.tap(find.text(id));
  nextPhoto = fixture(photo);
  await m.tap(_photograph);
}

Future<void> _save(Manual m) async {
  await m.tap(find.text(tr.reviewSavePlate));
  final save = find.widgetWithText(FilledButton, tr.saveSheetSave);
  await m.show(save);
  await m.tap(save);
}

void main() {
  chapter('petrifilm', (m) async {
    await m.start();
    await m.tap(_nav(tr.homeSamples));

    // Plan a film sample.
    await m.shot('1-new', [(find.text(tr.homeNewSample), Mark.tap)]);
    await m.tap(find.text(tr.homeNewSample));
    await showAt(m, find.text(tr.setupFilm));
    await m.shot('2-film', [(find.text(tr.setupFilm), Mark.tap)]);
    await m.tap(find.text(tr.setupFilm));

    await showAt(m, find.text(tr.filmType));
    await m.tap(find.text(PlateFormat.filmAc.text));
    await m.shot('3-types', [
      (find.text(PlateFormat.filmEc.text).last, Mark.tap),
    ]);
    await m.tap(find.text(PlateFormat.filmEc.text).last);

    await showAt(m, find.text(tr.filmType), alignment: 0.1);
    await m.shot('4-plan', [
      (field(find.text(tr.filmType)), Mark.look),
      (field(find.text(tr.setupFrom)), Mark.look),
      (field(find.text(tr.setupVolumePerPlate)), Mark.look),
    ]);
    await showAt(m, find.text(tr.setupSave));
    await m.tap(find.text(tr.setupSave));

    // Photograph and check.
    await m.shot('5-photograph', [(_photograph, Mark.tap)]);
    nextPhoto = fixture('film_ec.jpg');
    await m.tap(_photograph);
    await m.shot('6-review', [
      (
        find.ancestor(
          of: find.textContaining(filmResultText('ecoli')).first,
          matching: find.byType(Wrap),
        ),
        Mark.look,
      ),
      (find.textContaining(filmKindText('red')).last, Mark.look),
    ]);

    await showAt(m, find.text(tr.reviewModeKind), alignment: 1);
    await m.tap(find.text(tr.reviewModeKind));
    await tapPhoto(m, _ecRedGas);
    await m.shot('7-kind', [
      (find.text(tr.reviewModeKind), Mark.tap),
      (photoSpot(m, _ecRedGas, _colonyR), Mark.look),
    ]);
    await clearSpots(m);
    await m.tap(find.byTooltip(tr.reviewUndo));

    await m.tap(find.text(tr.reviewModeGas));
    await tapPhoto(m, _ecBlueNoGas);
    await m.shot('8-gas', [
      (find.text(tr.reviewModeGas), Mark.tap),
      (photoSpot(m, _ecBlueNoGas, _colonyR), Mark.look),
    ]);
    await clearSpots(m);
    await m.tap(find.byTooltip(tr.reviewUndo));

    await m.tap(find.text(tr.reviewSavePlate));
    final save = find.widgetWithText(FilledButton, tr.saveSheetSave);
    await m.show(save);
    await m.shot('9-save', [
      (find.textContaining('Petrifilm'), Mark.look),
      (_label(save), Mark.tap),
    ]);
    await m.tap(save);
    await showAt(m, find.text(filmResultText('ecoli')), alignment: 0.05);
    final value = find.textContaining(RegExp(r'^[\d.]+ × .*CFU/mL$'));
    await m.shot('10-result', [
      (value.at(0), Mark.look),
      (value.at(1), Mark.look),
    ]);

    // Enterobacteriaceae: the yellow zone.
    await m.back();
    await _photographSample(m, 'EB1', 'film_eb.jpg');
    await showAt(m, find.text(tr.reviewModeYellow), alignment: 1);
    await m.tap(find.text(tr.reviewModeYellow));
    await tapPhoto(m, _ebRed);
    await m.shot('11-zone', [
      (find.text(tr.reviewModeYellow), Mark.tap),
      (photoSpot(m, _ebRed, _colonyR), Mark.look),
    ]);
    await clearSpots(m);
    await m.tap(find.byTooltip(tr.reviewUndo));
    await _save(m);

    // A crowded aerobic count film: estimated from grid squares.
    await m.back();
    await _photographSample(m, 'AC1', 'film_ac_crowded.jpg');
    await m.shot('12-crowded', [
      (find.textContaining('≈').first, Mark.look),
      (find.text(tr.reviewModeSquares), Mark.tap),
    ]);
    await m.tap(find.text(tr.reviewModeSquares));
    final state = m.tester.state(find.byType(ReviewScreen));
    // ignore: avoid_dynamic_calls
    final square = (state as dynamic).debugSquareCentre(0) as Offset;
    await tapPhoto(m, square);
    await m.shot('13-squares', [
      (photoSpot(m, square, 60), Mark.look),
      (find.textContaining('≈').first, Mark.look),
    ]);
    await clearSpots(m);
    await _save(m);
    await showAt(m, find.text(filmResultText('aerobic')), alignment: 0.05);
    await m.shot('14-result', [
      (find.textContaining('CFU/mL').first, Mark.look),
    ]);
  });
}
