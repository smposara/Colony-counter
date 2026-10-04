import 'dart:io';
import 'dart:typed_data';

import 'package:colony_counter/core/calculator.dart';
import 'package:colony_counter/core/classical.dart';
import 'package:colony_counter/core/plate.dart';
import 'package:colony_counter/data/plate_record.dart';
import 'package:colony_counter/data/plate_store.dart';
import 'package:colony_counter/core/spots.dart';
import 'package:colony_counter/data/export.dart';
import 'package:colony_counter/data/sample_info.dart';
import 'package:colony_counter/data/storage/storage.dart';
import 'package:colony_counter/data/storage/storage_io.dart';
import 'package:flutter_test/flutter_test.dart';

PlateRecord _record(
  String id,
  int count,
  int dilutionExp, {
  String sample = 'S1',
}) => PlateRecord(
  id: id,
  createdAt: DateTime(2026, 10, 3, 12, int.parse(id)),
  imagePath: '$id.jpg',
  imageWidth: 1000,
  imageHeight: 1000,
  plate: const Plate(500, 500, 420),
  colonies: [for (var i = 0; i < count; i++) Colony(i.toDouble(), 0, 5)],
  autoCount: count,
  sampleId: sample,
  dilutionExp: dilutionExp,
);

void main() {
  test('record JSON round trip keeps edits', () {
    final r = _record('1', 3, 4).copyWith(
      colonies: const [
        Colony(1, 2, 3),
        Colony(4, 5, 6, n: 3),
        Colony(7, 8, 9, manual: true),
      ],
      notes: 'lid fogged',
      spreader: true,
    );
    final back = PlateRecord.fromJson(r.toJson());
    expect(back.count, 5);
    expect(back.added, 1);
    expect(back.notes, 'lid fogged');
    expect(back.spreader, isTrue);
    expect(back.dilution, closeTo(1e-4, 1e-12));
    expect(back.plate.radius, 420);
  });

  test('plate CSV and sample summary CSV', () async {
    final store = PlateStore(MemoryStorage());
    await store.load();
    await store.upsertSample(
      SampleInfo(
        sampleId: 'S1',
        experiment: 'E1',
        condition: 'Control',
        dilutions: [3, 4],
        replicates: 2,
      ),
    );
    await store.upsert(_record('1', 120, 3).copyWith(replicate: 1));
    await store.upsert(_record('2', 100, 3).copyWith(replicate: 2));
    await store.upsert(_record('3', 15, 4).copyWith(replicate: 1));

    final plates = platesCsv(store).trim().split('\n');
    expect(plates.first, startsWith('plate_id,date,sample_id,experiment'));
    expect(plates.length, 4);

    final samples = samplesCsv(store).trim().split('\n');
    expect(samples.length, 2);
    final cols = samples[1].split(',');
    final header = samples[0].split(',');
    String col(String name) => cols[header.indexOf(name)];
    expect(col('sample_id'), 'S1');
    expect(col('replicates_used'), '2');
    // Replicates: 120 and 100 colonies at 10^-3 → 1.2e6 and 1.0e6 CFU/mL.
    expect(double.parse(col('mean_cfu_per_ml')), closeTo(1.1e6, 1));
  });

  test('slots track which plates of a plan are done', () async {
    final info = SampleInfo(sampleId: 'S', dilutions: [4, 5], replicates: 2);
    expect(info.slots.length, 4);
    final done = [_record('1', 50, 4).copyWith(replicate: 1, sampleId: 'S')];
    final next = info.nextSlot(done)!;
    expect((next.dilutionExp, next.replicate), (4, 2));

    final drop = SampleInfo(
      sampleId: 'D',
      method: PlatingMethod.drop,
      dilutions: [3, 4, 5, 6],
      replicates: 3,
      dropLayout: DropLayout.dilutions,
    );
    expect(drop.slots.length, 3); // one plate per replicate
    expect(drop.unitVolumeMl, closeTo(0.01, 1e-12));
  });

  test('drop plate observations come from its spots', () {
    final r = _record('1', 0, 0).copyWith(
      volumeMl: 0.01,
      colonies:
          [for (var i = 0; i < 12; i++) Colony(100.0 + i, 100, 2)] +
          [for (var i = 0; i < 4; i++) Colony(500.0 + i, 100, 2)],
      spots: const [
        Spot(105, 100, 30, dilutionExp: 4, replicate: 1),
        Spot(502, 100, 30, dilutionExp: 5, replicate: 1),
      ],
    );
    final obs = r.observations();
    expect(obs.map((o) => o.count.count), [12, 4]);
    // Both drops are within the 3–30 range, so they are pooled.
    expect(
      r.estimateAlone(CountingRule.fdaBam).value,
      roundSig(16 / (0.01 * (1e-4 + 1e-5))),
    );
  });

  test('backup round trip restores plates, plans and photos', () async {
    final src = PlateStore(MemoryStorage());
    await src.load();
    await src.upsertSample(
      SampleInfo(sampleId: 'S1', condition: 'Control', timeH: 4),
    );
    final rec = _record('1', 30, 4).copyWith(sampleId: 'S1');
    await src.savePhoto(Uint8List.fromList([1, 2, 3, 4]), '1');
    await src.upsert(rec);

    final zip = await buildBackup(src);
    final dst = PlateStore(MemoryStorage());
    await dst.load();
    final summary = await restoreBackup(dst, zip);
    expect(
      (summary.platesAdded, summary.platesSkipped, summary.samplesAdded),
      (1, 0, 1),
    );
    expect(dst.records.single.count, 30);
    expect(dst.sampleInfo('S1').timeH, 4);
    expect(await dst.readPhoto(dst.records.single), [1, 2, 3, 4]);

    // Restoring again adds nothing new.
    final again = await restoreBackup(dst, zip);
    expect((again.platesAdded, again.platesSkipped), (0, 1));
    expect(
      () => restoreBackup(dst, Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
  });

  test('store persists records and settings', () async {
    final dir = await Directory.systemTemp.createTemp('cc_store');
    addTearDown(() => dir.delete(recursive: true));
    final store = PlateStore(DirectoryStorage(dir));
    await store.load();
    await store.upsert(_record('1', 10, 2));
    await store.upsert(_record('2', 30, 1, sample: 'S2'));
    await store.setRule(CountingRule.iso7218);

    final again = PlateStore(DirectoryStorage(dir));
    await again.load();
    expect(again.records.map((r) => r.id), ['2', '1']); // newest first
    expect(again.rule, CountingRule.iso7218);
    expect(again.samples().keys.toSet(), {'S1', 'S2'});

    await again.delete(again.records.first);
    expect(again.records.length, 1);
  });
}
