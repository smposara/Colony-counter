import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:colony_counter/core/plate.dart';
import 'package:colony_counter/data/export.dart';
import 'package:colony_counter/data/plate_record.dart';
import 'package:colony_counter/data/plate_store.dart';
import 'package:colony_counter/data/sample_info.dart';
import 'package:colony_counter/data/storage/journaled_storage.dart';
import 'package:colony_counter/data/storage/storage.dart';
import 'package:colony_counter/data/storage/storage_io.dart';
import 'package:flutter_test/flutter_test.dart';

class FailingStorage extends MemoryStorage {
  String? failKey;
  bool failPhotoDelete = false;
  @override
  Future<void> writeText(String key, String value) async {
    if (key == failKey) throw const FileSystemException('Disk full');
    await super.writeText(key, value);
  }

  @override
  Future<void> deletePhoto(String name) async {
    if (failPhotoDelete) throw const FileSystemException('Delete denied');
    await super.deletePhoto(name);
  }
}

PlateRecord record(String id, {String sample = 'A'}) => PlateRecord(
  id: id,
  createdAt: DateTime(2026, 10, 12),
  imagePath: '$id.jpg',
  imageWidth: 10,
  imageHeight: 10,
  plate: const Plate(5, 5, 4),
  colonies: const [],
  autoCount: 0,
  sampleId: sample,
);

void main() {
  test('a rejected commit rolls back memory and preserves the photo', () async {
    final backend = FailingStorage();
    final store = PlateStore(backend);
    await store.load();
    final r = record('1');
    await store.savePhoto(Uint8List.fromList([1]), r.id);
    await store.upsert(r);
    backend.failKey = JournaledStorage.journalKey;
    await expectLater(store.delete(r), throwsA(isA<FileSystemException>()));
    expect(store.records.single.id, r.id);
    expect(await store.readPhoto(r), isNotNull);
    final reopened = PlateStore(backend);
    await reopened.load();
    expect(reopened.records.single.id, r.id);
  });

  test('new capture failed before commit leaves no record or orphan photo; retry works', () async {
    final backend = FailingStorage()..failKey = JournaledStorage.journalKey;
    final store = PlateStore(backend);
    await store.load();
    await expectLater(
      store.saveCapture(record('1'), Uint8List.fromList([1])),
      throwsA(isA<FileSystemException>()),
    );
    expect(store.records, isEmpty);
    expect(await backend.readPhoto('1.jpg'), isNull);
    backend.failKey = null;
    await store.saveCapture(record('1'), Uint8List.fromList([1]));
    expect(store.records, hasLength(1));
  });

  test(
    'committed documents survive a failed materialisation and restart',
    () async {
      final backend = FailingStorage()..failKey = 'plates_index';
      final store = PlateStore(backend);
      await store.load();
      await store.upsert(record('1'));
      final reopened = PlateStore(backend);
      await reopened.load();
      expect(reopened.records.single.id, '1');
      backend.failKey = null;
      await reopened.upsert(record('2'));
      final again = PlateStore(backend);
      await again.load();
      expect(again.records, hasLength(2));
      expect(
        jsonDecode((await backend.readText(JournaledStorage.journalKey))!),
        isEmpty,
      );
    },
  );

  test('a sample rename is recovered as one transaction', () async {
    final backend = FailingStorage();
    final store = PlateStore(backend);
    await store.load();
    await store.upsert(record('1'));
    await store.upsertSample(
      SampleInfo(sampleId: 'A', createdAt: DateTime(2026)),
    );
    backend.failKey = 'samples';
    await store.upsertSample(
      SampleInfo(sampleId: 'B', createdAt: DateTime(2026)),
      previousId: 'A',
    );
    final reopened = PlateStore(backend);
    await reopened.load();
    expect(reopened.platesOf('B'), hasLength(1));
    expect(reopened.hasPlan('B'), isTrue);
    expect(reopened.hasPlan('A'), isFalse);
  });

  test('failed photo cleanup cannot resurrect a deleted record', () async {
    final backend = FailingStorage();
    final store = PlateStore(backend);
    await store.load();
    await store.upsert(record('1'));
    backend.failPhotoDelete = true;
    await store.delete(record('1'));
    final reopened = PlateStore(backend);
    await reopened.load();
    expect(reopened.records, isEmpty);
  });

  test('overlapping native writes are complete and last-write wins', () async {
    final dir = await Directory.systemTemp.createTemp('cc_atomic');
    addTearDown(() => dir.delete(recursive: true));
    final backend = DirectoryStorage(dir);
    await Future.wait([
      for (var i = 0; i < 30; i++)
        backend.writeText('settings', jsonEncode({'n': i})),
    ]);
    expect(jsonDecode((await backend.readText('settings'))!)['n'], 29);
    expect(dir.listSync().where((f) => f.path.endsWith('.tmp')), isEmpty);
  });

  test(
    'the photo cache is bounded by bytes, including one oversized photo',
    () async {
      final store = PlateStore(MemoryStorage());
      for (var i = 0; i < 4; i++) {
        await store.savePhoto(Uint8List(8 * 1024 * 1024), '$i');
        expect(
          store.cachedPhotoBytes,
          lessThanOrEqualTo(PlateStore.photoCacheBudget),
        );
      }
      await store.savePhoto(
        Uint8List(PlateStore.photoCacheBudget + 1),
        'large',
      );
      expect(
        store.cachedPhotoBytes,
        lessThanOrEqualTo(PlateStore.photoCacheBudget),
      );
    },
  );

  test('backup restores interface preferences as well as plates', () async {
    final store = PlateStore(MemoryStorage());
    await store.setDefaults(
      language: 'th',
      theme: 'dark',
      zoneDisclaimerSeen: true,
    );
    await store.upsert(record('1'));
    final target = PlateStore(MemoryStorage());
    await restoreBackup(target, await buildBackup(store));
    expect(target.language, 'th');
    expect(target.theme, 'dark');
    expect(target.zoneDisclaimerSeen, isTrue);
  });
  test(
    'legacy plate metadata migrates and untouched records are not rewritten',
    () async {
      final backend = RecordingStorage();
      await backend.writeText(
        'plates',
        jsonEncode([record('1').toJson(), record('2').toJson()]),
      );
      final store = PlateStore(backend);
      await store.load();
      await store.upsert(record('1').copyWith(notes: 'edited'));
      final reopened = PlateStore(backend);
      await reopened.load();
      expect(reopened.records, hasLength(2));
      backend.keys.clear();
      await reopened.upsert(
        reopened.records
            .firstWhere((r) => r.id == '1')
            .copyWith(notes: 'again'),
      );
      final two =
          'plates_${base64Url.encode(utf8.encode('2')).replaceAll('=', '')}';
      expect(backend.keys, isNot(contains(two)));
    },
  );
}

class RecordingStorage extends MemoryStorage {
  final keys = <String>[];
  @override
  Future<void> writeText(String key, String value) async {
    keys.add(key);
    await super.writeText(key, value);
  }
}
