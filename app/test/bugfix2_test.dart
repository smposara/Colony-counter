import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:colony_counter/core/calculator.dart';
import 'package:colony_counter/core/plate.dart';
import 'package:colony_counter/data/export.dart';
import 'package:colony_counter/data/plate_record.dart';
import 'package:colony_counter/data/plate_store.dart';
import 'package:colony_counter/data/storage/storage_io.dart';
import 'package:flutter_test/flutter_test.dart';

PlateRecord _plate(String id, String image) => PlateRecord(
  id: id,
  createdAt: DateTime(2026, 10, 4),
  imagePath: image,
  imageWidth: 10,
  imageHeight: 10,
  plate: const Plate(5, 5, 4),
  colonies: const [],
  autoCount: 0,
);

Uint8List _backup(
  List<PlateRecord> plates,
  Map<String, List<int>> photos, {
  Map<String, dynamic>? settings,
}) {
  final manifest = utf8.encode(
    jsonEncode({
      'format': 'colony-counter-backup',
      'version': 1,
      'settings': ?settings,
      'samples': [],
      'plates': [for (final p in plates) p.toJson()],
    }),
  );
  final archive = Archive()
    ..addFile(
      ArchiveFile('colony-counter-backup.json', manifest.length, manifest),
    );
  photos.forEach((name, bytes) {
    archive.addFile(ArchiveFile('photos/$name', bytes.length, bytes));
  });
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

Future<PlateStore> _store() async {
  final root = await Directory.systemTemp.createTemp('cc_bug2');
  addTearDown(() => root.delete(recursive: true));
  final store = PlateStore(DirectoryStorage(root));
  await store.load();
  return store;
}

void main() {
  test('a TNTC plate is never picked as the closest count', () {
    // 10^-3 is TNTC (120 counted before giving up), 10^-5 has 5 colonies:
    // the estimate must come from the real count, not the lower bound.
    final e = estimate(const [
      PlateCount(120, 1e-3, tntc: true),
      PlateCount(5, 1e-5),
    ]);
    expect(e.platesUsed.single.tntc, isFalse);
    expect(e.platesUsed.single.count, 5);
  });

  test('a plate listed twice in one backup is imported once', () async {
    final store = await _store();
    final p = _plate('1700000000000', '1700000000000.jpg');
    final s = await restoreBackup(
      store,
      _backup(
        [p, p],
        {
          '1700000000000.jpg': [1, 2, 3],
        },
      ),
    );
    expect(store.records, hasLength(1));
    expect(s.platesAdded, 1);
    expect(s.platesSkipped, 1);
  });

  test('restored photos never overwrite one another', () async {
    final store = await _store();
    // Both unsafe names fall back to "restored_a_b.jpg".
    await restoreBackup(
      store,
      _backup(
        [_plate('a/b', '../x.jpg'), _plate('a_b', '../y.jpg')],
        {
          '../x.jpg': [1],
          '../y.jpg': [2],
        },
      ),
    );
    final names = store.records.map((r) => r.imagePath).toSet();
    expect(names, hasLength(2));
    final photos = {
      for (final r in store.records) r.id: await store.readPhoto(r),
    };
    expect(photos['a/b'], [1]);
    expect(photos['a_b'], [2]);
  });

  test('settings come back only when restoring onto an empty device', () async {
    final settings = {
      'rule': 'iso7218',
      'volume_ml': 1.0,
      'operator': 'PS',
      'medium': 'PCA',
      'format': 'dish60',
      'accuracy_every': 5,
    };
    final fresh = await _store();
    await restoreBackup(
      fresh,
      _backup([_plate('1', '1.jpg')], {}, settings: settings),
    );
    expect(fresh.rule, CountingRule.iso7218);
    expect(fresh.defaultVolumeMl, 1.0);
    expect(fresh.defaultOperator, 'PS');
    expect(fresh.defaultMedium, 'PCA');
    expect(fresh.defaultFormat, PlateFormat.dish60);
    expect(fresh.accuracyCheckEvery, 5);

    final used = await _store();
    await used.upsert(_plate('mine', 'mine.jpg'));
    await restoreBackup(
      used,
      _backup([_plate('2', '2.jpg')], {}, settings: settings),
    );
    expect(used.rule, CountingRule.fdaBam);
    expect(used.defaultVolumeMl, isNot(1.0));
  });
}
