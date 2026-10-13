import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/worker/client.dart';
import 'plate_store.dart';
import 'plate_record.dart';
import 'training_model.dart';
import 'training_metadata.dart';
import 'streaming_zip.dart';
export 'training_model.dart';

Stream<Uint8List> buildTrainingExportStream(
  PlateStore store, {
  TrainingSelection selection = TrainingSelection.corrected,
}) {
  return store.readSnapshot(() {
    final plates = trainingPlates(store, selection);
    Stream<ZipEntrySource> entries() async* {
      final present = <PlateRecord>[];
      for (final r in plates) {
        final dot = r.imagePath.lastIndexOf('.');
        final ext = dot < 0 ? 'jpg' : r.imagePath.substring(dot + 1);
        yield ZipEntrySource('images/${r.id}.$ext', () async {
          final bytes = await store.backend.readPhoto(r.imagePath);
          if (bytes != null) present.add(r);
          return bytes;
        });
      }
      final records = <Map<String, dynamic>>[];
      for (var i = 0; i < present.length; i++) {
        records.add(present[i].toJson());
        if (i % 16 == 15) await Future<void>.delayed(Duration.zero);
      }
      final job = <String, dynamic>{
        'kind': 'training',
        'selection': selection.name,
        'records': records,
      };
      final Map<String, String> files;
      if (kIsWeb) {
        final result = await runPhotoJob(Uint8List(0), job);
        files = (result['files'] as Map).cast<String, String>();
      } else {
        files = await compute(trainingMetadata, job);
      }
      for (final e in files.entries) {
        yield ZipEntrySource(
          e.key,
          () async => Uint8List.fromList(utf8.encode(e.value)),
        );
      }
    }

    return streamZip(entries());
  });
}

Future<Uint8List> buildTrainingExport(
  PlateStore store, {
  TrainingSelection selection = TrainingSelection.corrected,
}) async {
  final out = BytesBuilder(copy: false);
  await for (final chunk in buildTrainingExportStream(
    store,
    selection: selection,
  )) {
    out.add(chunk);
  }
  return out.takeBytes();
}
