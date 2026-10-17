// Builds the app's built-in example data, assets/examples/examples.zip.
// Not named _test.dart, so the normal test run skips it. From app/:
//
//   python ../ml/scripts/make_examples.py      # photos → build/examples/
//   flutter test test/examples/make_examples_gen.dart
//
// Every photo is counted or measured by the app's own pipeline, saved as the
// app would save it, and packed with buildBackup, without the settings.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:colony_counter/core/pipeline.dart';
import 'package:colony_counter/core/stats.dart';
import 'package:colony_counter/core/zones.dart';
import 'package:colony_counter/data/export.dart';
import 'package:colony_counter/data/plate_record.dart';
import 'package:colony_counter/data/plate_store.dart';
import 'package:colony_counter/data/sample_info.dart';
import 'package:colony_counter/data/storage/storage.dart';
import 'package:colony_counter/data/zone_record.dart';
import 'package:flutter_test/flutter_test.dart';

const _photos = 'build/examples';
const _out = 'assets/examples/examples.zip';

/// Test items on the zone plate, clockwise from 12 o'clock.
const _zoneLabels = ['Ext A', 'Amp 10', 'Ext B', 'Ext C', 'Ext D', 'Neg'];

final _start = DateTime(2026, 10, 1, 9);

Future<PlateRecord> _plate(
  PlateStore store,
  String photo, {
  required String id,
  required String sampleId,
  required int dilutionExp,
  int replicate = 1,
  required Duration after,
}) async {
  final bytes = File('$_photos/$photo.jpg').readAsBytesSync();
  final res = countPhoto(bytes);
  return store.saveCapture(
    PlateRecord(
      id: '$kExampleIdPrefix$id',
      createdAt: _start.add(after),
      imagePath: '',
      imageWidth: res.imageWidth,
      imageHeight: res.imageHeight,
      plate: res.plate,
      colonies: res.colonies,
      autoCount: res.count,
      flags: res.flags,
      sampleId: sampleId,
      dilutionExp: dilutionExp,
      replicate: replicate,
      spreader: res.flags.contains('spreader'),
      tntc: res.flags.contains('tntc'),
      guided: true,
    ),
    bytes,
  );
}

void main() {
  test('make assets/examples/examples.zip', () async {
    final store = PlateStore(MemoryStorage());
    await store.load();

    // A lake-water sample: 10⁻⁴ and 10⁻⁵ photographed, 10⁻⁶ still to do.
    const lake = 'Example – lake water';
    await store.upsertSample(
      SampleInfo(
        sampleId: lake,
        // Sorts after the disinfectant set, which Compare then opens on.
        experiment: 'Example – lake survey',
        dilutions: const [4, 5, 6],
        replicates: 2,
        medium: 'Plate Count Agar',
        incubationTempC: 30,
        incubationH: 72,
        tags: const [kExampleTag],
        createdAt: _start,
      ),
    );
    for (final (photo, id, exp, rep) in [
      ('lake_e4_r1', 'lake-e4-r1', 4, 1),
      ('lake_e4_r2', 'lake-e4-r2', 4, 2),
      ('lake_e5_r1', 'lake-e5-r1', 5, 1),
      ('lake_e5_r2', 'lake-e5-r2', 5, 2),
    ]) {
      await _plate(
        store,
        photo,
        id: id,
        sampleId: lake,
        dilutionExp: exp,
        replicate: rep,
        after: Duration(minutes: 10 * (exp - 4) + rep),
      );
    }

    // A disinfectant time-kill: control and treated at 0 h and 2 h. The
    // treated 2 h sample is plated two dilutions lower.
    const disinfectant = 'Example – disinfectant';
    for (final (i, (condition, timeH, exp)) in const [
      ('Control', 0.0, 5),
      ('Control', 2.0, 5),
      ('Treated', 0.0, 5),
      ('Treated', 2.0, 3),
    ].indexed) {
      final h = timeH.round();
      final id = 'Example – ${condition.toLowerCase()} $h h';
      final at = _start.add(Duration(days: 1, hours: h, minutes: i));
      await store.upsertSample(
        SampleInfo(
          sampleId: id,
          experiment: disinfectant,
          condition: condition,
          timeH: timeH,
          dilutions: [exp],
          replicates: 1,
          strain: 'E. coli',
          medium: 'Nutrient Agar',
          incubationTempC: 37,
          incubationH: 24,
          tags: const [kExampleTag],
          createdAt: at,
        ),
      );
      final photo = '${condition.toLowerCase()}_${h}h';
      await _plate(
        store,
        photo,
        id: photo.replaceAll('_', '-'),
        sampleId: id,
        dilutionExp: exp,
        after: Duration(days: 1, hours: h, minutes: i + 30),
      );
    }

    // An inhibition-zone plate, its disks labelled clockwise from the top.
    final zoneBytes = File('$_photos/zones.jpg').readAsBytesSync();
    final zones = measureZonesInPhoto((zoneBytes, const ZoneOptions()));
    await store.saveZoneCapture(
      ZoneRecord.fromResult(
        zones,
        id: '${kExampleIdPrefix}zones',
        imagePath: '',
        createdAt: _start.add(const Duration(days: 2)),
        labels: _zoneLabels,
        experiment: 'Example – extracts',
        organism: 'S. aureus',
      ),
      zoneBytes,
    );

    // What the app makes of them.
    for (final s in store.allSamples()) {
      final plates = store.platesOf(s.sampleId);
      final r = s.analyse(plates, store.rule).stats;
      // ignore: avoid_print
      print(
        '${s.sampleId}: ${[for (final p in plates) '1e-${p.dilutionExp} R${p.replicate} ${p.count}']} '
        '→ ${r.mean.toStringAsExponential(2)} ± ${r.sd.toStringAsExponential(1)}, '
        'log ${r.log10Mean.toStringAsFixed(2)}; next ${s.nextSlot(plates)?.dilutionExp}',
      );
    }
    ReplicateStats stats(String id) =>
        store.sampleInfo(id).analyse(store.platesOf(id), store.rule).stats;
    final reduction = Reduction(
      stats('Example – control 2 h'),
      stats('Example – treated 2 h'),
    );
    // ignore: avoid_print
    print('log reduction at 2 h: ${reduction.logReduction.toStringAsFixed(2)}');
    final z = store.zoneRecords.single;
    // ignore: avoid_print
    print(
      'zones: ${[for (final m in z.marks) '${m.label} ${m.reportedMm(z.diskMm)}'].join(', ')}',
    );

    // The backup, minus its settings.
    final zip = ZipDecoder().decodeBytes(
      await buildBackup(store, includeExamples: true),
    );
    final out = Archive();
    for (final f in zip.files) {
      var bytes = f.content as List<int>;
      if (f.name == 'colony-counter-backup.json') {
        final m = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        m.remove('settings');
        bytes = utf8.encode(jsonEncode(m));
      }
      // Only the manifest and photos are needed to restore.
      if (f.name.endsWith('.csv')) continue;
      out.addFile(ArchiveFile(f.name, bytes.length, bytes));
    }
    final file = File(_out)..createSync(recursive: true);
    file.writeAsBytesSync(ZipEncoder().encode(out));
    // ignore: avoid_print
    print('$_out: ${(file.lengthSync() / 1024).round()} KB');
  });
}
