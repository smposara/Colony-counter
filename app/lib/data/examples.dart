import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'export.dart';
import 'export_source.dart';
import 'plate_store.dart';
import 'sample_info.dart';

/// Built-in example data, so a new user can try every tab without a plate:
/// a backup zip made by test/examples/make_examples_gen.dart from synthetic
/// photos counted by the app itself. Example plate and zone-plate ids start
/// with [kExampleIdPrefix]; example samples are [kExampleSampleIds], tagged
/// [kExampleTag], and any plate in one is example data too. The zip
/// has no settings, so loading it never changes the language, theme or
/// defaults.
const kExamplesAsset = 'assets/examples/examples.zip';

/// Reads the bundled examples zip; tests replace it.
typedef ExamplesLoader = Future<Uint8List> Function();

Future<Uint8List> _bundledExamples() async =>
    (await rootBundle.load(kExamplesAsset)).buffer.asUint8List();

/// Any example plate, zone plate or sample is still here.
bool hasExamples(PlateStore store) =>
    store.records.any((r) => isExamplePlate(store, r)) ||
    store.zoneRecords.any((r) => r.isExample) ||
    store.samplePlans.any((s) => s.isExample);

/// Loads the examples (again). Examples already here are skipped. With
/// [onlyIntoEmpty], nothing is loaded unless the app is still empty when the
/// examples go in.
Future<void> addExamples(
  PlateStore store, {
  ExamplesLoader load = _bundledExamples,
  bool onlyIntoEmpty = false,
}) async {
  await restoreBackup(store, await load(), onlyIntoEmpty: onlyIntoEmpty);
}

/// Deletes the example plates, zone plates and their photos, and the example
/// samples with every plate in them (the user's too: everything in an
/// example sample is example data).
Future<void> removeExamples(PlateStore store) async {
  for (final r in store.records.where((r) => isExamplePlate(store, r))) {
    await store.delete(r);
  }
  for (final r in store.zoneRecords.where((r) => r.isExample)) {
    await store.deleteZone(r);
  }
  for (final s in store.samplePlans.where((s) => s.isExample)) {
    await store.deleteSample(s.sampleId);
  }
}

/// At first launch: loads the examples into an empty app, once. An app that
/// already has data (an upgrade), or gets some while the examples load (a
/// restored backup, a first plate), only remembers that they were offered.
/// Failures are logged, never thrown: the app starts without examples.
Future<void> offerExamples(
  PlateStore store, {
  ExamplesLoader load = _bundledExamples,
}) async {
  if (store.examplesOffered) return;
  try {
    if (store.records.isEmpty &&
        store.samplePlans.isEmpty &&
        store.zoneRecords.isEmpty) {
      await addExamples(store, load: load, onlyIntoEmpty: true);
    }
  } catch (e) {
    debugPrint('Example data not loaded: $e');
  }
  try {
    await store.setExamplesOffered();
  } catch (e) {
    debugPrint('Example data offer not saved: $e');
  }
}
