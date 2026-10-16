import 'dart:io';

import 'package:colony_counter/l10n/l10n.dart';
import 'package:colony_counter/ui/multi_plate_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';
import 'samples_helpers.dart';

/// Four plates on a dark table: 1240 × 1200 px, plates of radius 244 px.
final _photo = File('test/manual/multi_plates.jpg').readAsBytesSync();
const _centres = [
  Offset(310, 290),
  Offset(930, 290),
  Offset(310, 910),
  Offset(930, 910),
];

/// Where the photo is drawn on screen.
Rect _photoRect(Manual m) => m.tester.getRect(
  find.descendant(
    of: find.byType(MultiPlateScreen),
    matching: find.byType(Image),
  ),
);

/// Screen point of [p] (photo pixels).
Offset _at(Manual m, Offset p) {
  final r = _photoRect(m);
  return r.topLeft + p * (r.width / 1240);
}

/// Screen box around the plate centred at [p].
Rect _plate(Manual m, Offset p, {double radius = 244}) => Rect.fromCircle(
  center: _at(m, p),
  radius: radius * _photoRect(m).width / 1240,
);

Future<void> _tapAt(Manual m, Offset p) async {
  await m.tester.tapAt(_at(m, p));
  await m.settle();
}

/// Counts and saves the plate at [p] with the review screen's defaults.
Future<void> _savePlate(Manual m, Offset p) async {
  await _tapAt(m, p);
  await m.tap(find.text(tr.reviewSavePlate));
  await m.tap(find.text(tr.saveSheetSave));
}

void main() {
  chapter('multi', (m) async {
    await m.start(seed: (store) => store.upsertSample(planFor('Lake-A')));

    // From the Plates tab.
    await snap(m, '1-grid', [(find.byTooltip(tr.homeSeveralPlates), Mark.tap)]);
    await m.tap(find.byTooltip(tr.homeSeveralPlates));
    await snap(m, '2-source', [
      (find.text(tr.multiTakePhoto), Mark.tap),
      (find.text(tr.multiChoosePhoto), Mark.tap),
    ]);
    nextPhoto = _photo;
    await m.tap(find.text(tr.multiTakePhoto));
    await snap(m, '3-found', [
      (find.text(tr.multiPlatesFound(4)), Mark.look),
      (_plate(m, _centres[0]), Mark.tap),
    ]);
    await m.back();

    // From a sample: the plates take its plan's places in order.
    await m.tap(find.text(tr.homeSamples));
    await m.tap(find.text('Lake-A'));
    await m.tap(find.byType(PopupMenuButton<String>));
    await snap(m, '4-menu', [(find.text(tr.samplesMulti), Mark.tap)]);
    await m.tap(find.text(tr.samplesMulti));
    await m.tap(find.text(tr.multiTakePhoto));
    await snap(m, '5-slots', [
      (find.byType(Wrap), Mark.look),
      (find.byTooltip(tr.multiAddRemove), Mark.tap),
    ]);

    // Add or remove circles.
    await m.tap(find.byTooltip(tr.multiAddRemove));
    await snap(m, '6-edit', [
      (_plate(m, _centres[3]), Mark.tap),
      (find.text(tr.multiEditHint), Mark.look),
    ]);
    await _tapAt(m, _centres[3]);
    await snap(m, '7-add', [(_plate(m, _centres[3], radius: 60), Mark.tap)]);
    await _tapAt(m, _centres[3]);
    await snap(m, '8-done', [(find.byTooltip(tr.multiDone), Mark.tap)]);
    await m.tap(find.byTooltip(tr.multiDone));

    // Count each plate.
    await _tapAt(m, _centres[0]);
    await snap(m, '9-review', [(find.text(tr.reviewSavePlate), Mark.tap)]);
    await m.tap(find.text(tr.reviewSavePlate));
    await m.tap(find.text(tr.saveSheetSave));
    await snap(m, '10-saved', [
      (_plate(m, _centres[0]), Mark.look),
      (_plate(m, _centres[1]), Mark.tap),
    ]);
    for (final p in _centres.skip(1)) {
      await _savePlate(m, p);
    }
    await snap(m, '11-all', [(find.text(tr.multiAllSaved), Mark.look)]);
    await m.back();
    await snap(m, '12-sample', [
      (find.byType(Wrap).first, Mark.look),
      (find.textContaining('CFU/mL').first, Mark.look),
    ]);
  });
}
