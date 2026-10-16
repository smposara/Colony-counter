import 'dart:typed_data';

import 'package:colony_counter/data/export.dart';
import 'package:colony_counter/data/plate_store.dart';
import 'package:colony_counter/data/sample_info.dart';
import 'package:colony_counter/data/storage/storage.dart';
import 'package:colony_counter/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'data_helpers.dart';
import 'harness.dart';

Future<void> _menu(Manual m) => m.tap(find.byType(PopupMenuButton<String>));

/// A backup made on another phone: two plates of a new sample and one plate
/// that is already here.
Future<Uint8List> _otherPhoneBackup() async {
  final other = PlateStore(MemoryStorage());
  await other.load();
  await other.upsertSample(SampleInfo(sampleId: 'S9', dilutions: const [5]));
  for (var i = 0; i < 2; i++) {
    await seedPlate(
      other,
      id: 'phone2_$i',
      photo: i == 0 ? 'backlit.jpg' : 'sparse.jpg',
      at: DateTime(2026, 10, 12, 9 + i),
      sample: 'S9',
      dilution: 5,
      replicate: i + 1,
    );
  }
  await seedPlate(
    other,
    id: 'new3',
    photo: 'medium.jpg',
    at: DateTime(2026, 10, 4, 9),
    sample: 'S7',
  );
  return buildBackup(other);
}

void main() {
  chapter('data', (m) async {
    await m.start(seed: (store) => seedAccuracy(store, recent: 4));

    // Export CSV.
    await _menu(m);
    await m.shot('1-csv', [(find.text(tr.homeExportCsv), Mark.tap)]);
    await m.back();

    // Back up and restore.
    await _menu(m);
    await m.shot('2-backup', [(find.text(tr.homeBackUpAll), Mark.tap)]);
    await m.shot('3-restore', [(find.text(tr.homeRestore), Mark.tap)]);
    await m.back();

    // What the app does with the picked zip (the file picker cannot show
    // here): the same restore and message as the menu item.
    final zip = await m.tester.runAsync(_otherPhoneBackup);
    final r = (await m.tester.runAsync(() => restoreBackup(m.store, zip!)))!;
    final plates = tr.homeNPlates(r.platesAdded);
    final samples = tr.homeNSamples(r.samplesAdded);
    ScaffoldMessenger.of(m.context).showSnackBar(
      SnackBar(
        content: Text(
          r.platesSkipped > 0
              ? tr.homeRestoredKept(plates, samples, r.platesSkipped)
              : tr.homeRestored(plates, samples),
        ),
      ),
    );
    await m.tester.pump();
    await m.tester.pump(const Duration(milliseconds: 500));
    await m.shot('4-restored', [
      (find.byType(SnackBar), Mark.look),
      (
        find
            .ancestor(
              of: find.textContaining('S9').first,
              matching: find.byType(ListTile),
            )
            .first,
        Mark.look,
      ),
    ]);
    ScaffoldMessenger.of(m.context).hideCurrentSnackBar();
    await m.settle();

    // Training data.
    await _menu(m);
    await m.shot('5-training', [(find.text(tr.homeExportTraining), Mark.tap)]);
    await m.tap(find.text(tr.homeExportTraining));
    await m.shot('6-choose', [
      (find.text(tr.trainingChecked), Mark.tap),
      (find.text(tr.trainingCorrected), Mark.tap),
      (find.text(tr.trainingAll), Mark.tap),
    ]);
  });
}
