import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:colony_counter/core/classical.dart';
import 'package:colony_counter/core/labels.dart';
import 'package:colony_counter/core/plate.dart';
import 'package:colony_counter/core/timelapse.dart';
import 'package:colony_counter/data/export.dart';
import 'package:colony_counter/data/plate_record.dart';
import 'package:colony_counter/data/plate_store.dart';
import 'package:colony_counter/data/storage/storage_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a label with broken %-encoding is not a label (no exception)', () {
    expect(PlateLabel.parse('CC1;s=50%'), isNull);
    expect(PlateLabel.parse('CC1;s=%E0%A4'), isNull);
    expect(PlateLabel.parse('CC1;s=50%25')!.sampleId, '50%');
  });

  test('restoring a backup cannot write outside the photo folder', () async {
    final root = await Directory.systemTemp.createTemp('cc_restore');
    addTearDown(() => root.delete(recursive: true));
    final store = PlateStore(DirectoryStorage(root));
    await store.load();
    final evil = PlateRecord(
      id: 'p/1',
      createdAt: DateTime(2026, 10, 4),
      imagePath: '../settings.json',
      imageWidth: 10,
      imageHeight: 10,
      plate: const Plate(5, 5, 4),
      colonies: const [],
      autoCount: 0,
    );
    final manifest = utf8.encode(
      jsonEncode({
        'format': 'colony-counter-backup',
        'version': 1,
        'samples': [],
        'plates': [evil.toJson()],
      }),
    );
    final photo = Uint8List.fromList([1, 2, 3]);
    final archive = Archive()
      ..addFile(
        ArchiveFile('colony-counter-backup.json', manifest.length, manifest),
      )
      ..addFile(ArchiveFile('photos/../settings.json', photo.length, photo));
    await restoreBackup(
      store,
      Uint8List.fromList(ZipEncoder().encode(archive)),
    );

    final saved = store.records.single;
    expect(saved.imagePath, 'restored_p_1.jpg');
    expect(await store.readPhoto(saved), photo);
    // Nothing was written next to the photo folder.
    final outside = root
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.path)
        .where((p) => p.endsWith('settings.json'));
    expect(outside, isEmpty);
  });

  test('time-lapse photos with the same time do not double-count colonies', () {
    const plate = Plate(500, 500, 450);
    final res = analyseTimelapse([
      const TimelapseFrame(0, plate, [Colony(600, 500, 3)]),
      const TimelapseFrame(0, plate, [
        Colony(600, 500, 4),
        Colony(300, 300, 3),
      ]),
    ]);
    expect(res.newPerFrame, [1, 1]);
  });
}
