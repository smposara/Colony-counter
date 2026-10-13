import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:colony_counter/core/classical.dart';
import 'package:colony_counter/core/plate.dart';
import 'package:colony_counter/data/export.dart';
import 'package:colony_counter/data/export_metadata.dart';
import 'package:colony_counter/data/plate_record.dart';
import 'package:colony_counter/data/plate_store.dart';
import 'package:colony_counter/data/storage/storage.dart';
import 'package:colony_counter/data/streaming_zip.dart';
import 'package:colony_counter/data/training_export.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Uint8List> collect(Stream<Uint8List> stream) async {
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    bytes.add(chunk);
  }
  return bytes.takeBytes();
}

PlateRecord plate(String id) => PlateRecord(
  id: id,
  createdAt: DateTime(2026),
  imagePath: '$id.jpg',
  imageWidth: 100,
  imageHeight: 100,
  plate: const Plate(50, 50, 40),
  colonies: const [Colony(50, 50, 3)],
  autoCount: 1,
  verified: true,
  sampleId: 'sample',
);
void main() {
  test('streamed ZIP is independently readable with UTF8 names, empty files and large entries', () async {
    final photo = Uint8List.fromList(List.generate(200000, (i) => i % 251));
    final bytes = await collect(
      streamZip(
        Stream.fromIterable([
          ZipEntrySource('ภาพ.jpg', () async => photo),
          ZipEntrySource('empty.txt', () async => Uint8List(0)),
        ]),
      ),
    );
    final zip = ZipDecoder().decodeBytes(bytes, verify: true);
    expect(zip.findFile('ภาพ.jpg')!.content, photo);
    expect(zip.findFile('empty.txt')!.size, 0);
  });
  test('stream backpressure loads only the requested photo', () async {
    var reads = 0;
    final entries = Stream.fromIterable([
      for (var i = 0; i < 1000; i++)
        ZipEntrySource('$i.jpg', () async {
          reads++;
          return Uint8List(1024 * 1024);
        }),
    ]);
    final iterator = StreamIterator(streamZip(entries));
    expect(reads, 0);
    await iterator.moveNext();
    expect(reads, 1);
    await iterator.cancel();
    expect(reads, 1);
  });
  test(
    'backup stream writes directly to a file and restores all metadata/photos',
    () async {
      final backend = MemoryStorage();
      final store = PlateStore(backend);
      for (var i = 0; i < 4; i++) {
        await backend.writePhoto('$i.jpg', Uint8List.fromList([i, 1, 2, 3]));
        await store.upsert(plate('$i'));
      }
      final dir = await Directory.systemTemp.createTemp('cc_stream');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/backup.zip');
      final sink = file.openWrite();
      await sink.addStream(buildBackupStream(store));
      await sink.close();
      final target = PlateStore(MemoryStorage());
      await restoreBackup(target, await file.readAsBytes());
      expect(target.records, hasLength(4));
      expect(
        await target.readPhoto(target.records.firstWhere((r) => r.id == '3')),
        [3, 1, 2, 3],
      );
      expect(store.cachedPhotoBytes, 0); // Export bypassed the UI image cache.
    },
  );
  test('training stream preserves COCO, YOLO, negative examples and skips missing images', () async {
    final backend = MemoryStorage();
    final store = PlateStore(backend);
    await backend.writePhoto('1.jpg', Uint8List.fromList([1, 2]));
    await store.upsert(plate('1'));
    await store.upsert(plate('missing'));
    final bytes = await collect(
      buildTrainingExportStream(store, selection: TrainingSelection.all),
    );
    final zip = ZipDecoder().decodeBytes(bytes, verify: true);
    final coco = jsonDecode(
      utf8.decode(zip.findFile('annotations.json')!.content as List<int>),
    );
    expect(coco['images'], hasLength(1));
    expect(coco['annotations'], hasLength(1));
    expect(zip.findFile('images/1.jpg')!.content, [1, 2]);
    expect(zip.findFile('labels/1.txt'), isNotNull);
    expect(zip.findFile('images/missing.jpg'), isNull);
  });
  test(
    'worker export metadata preserves CSV results and portable backup schema',
    () {
      final r = plate('1');
      final data = <String, dynamic>{
        'backup': true,
        'rule': 'fdaBam',
        'settings': {'language': 'th'},
        'records': [r.toJson()],
        'zones': [],
        'samples': [],
        'calibrations': [],
        'panels': [],
        'created_at': 'now',
      };
      final result = exportMetadata(data);
      final files = (result['files'] as Map).cast<String, String>();
      final manifest = jsonDecode(files['colony-counter-backup.json']!);
      expect(manifest['version'], 1);
      expect(manifest['plates'].single['id'], '1');
      expect(files['plates.csv'], contains('sample'));
      expect(result['photos'], ['1.jpg']);
    },
  );
  test('export snapshot delays writes and cancellation releases the mutation queue', () async {
    final store = PlateStore(MemoryStorage());
    final r = plate('1');
    await store.upsert(r);
    final iterator = StreamIterator(
      store.readSnapshot(() => Stream<int>.fromIterable([1, 2])),
    );
    await iterator.moveNext();
    var deleted = false;
    final deletion = store.delete(r).then((_) => deleted = true);
    await Future<void>.delayed(Duration.zero);
    expect(deleted, isFalse);
    await iterator.cancel();
    await deletion;
    expect(deleted, isTrue);
    expect(store.records, isEmpty);
  });
}
