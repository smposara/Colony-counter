import 'package:flutter/foundation.dart';

import 'drop_layout.dart';
import 'annotate.dart';
import 'labels.dart';
import 'plate.dart';
import 'petrifilm.dart';
import 'pipeline.dart';
import 'zones.dart';
import 'worker/client.dart';
import 'worker/protocol.dart';

CountResult _count((Uint8List, CountOptions) job) => countPhoto(job.$1, job.$2);

/// [countPhoto] off the UI thread on phones (a background isolate).
///
/// Browsers use a dedicated Web Worker, keeping gestures and progress smooth.
Future<CountResult> countPhotoInBackground(
  Uint8List bytes, [
  CountOptions options = const CountOptions(),
]) async {
  if (kIsWeb) {
    return readCount(await runPhotoJob(bytes, countJob(options)));
  }
  return compute(_count, (bytes, options));
}

/// Counts a dry-film photo off the UI thread (in a Web Worker on browsers).
Future<FilmResult> countFilmInBackground(FilmJob job) async {
  if (kIsWeb) {
    return readFilm(await runPhotoJob(job.bytes, filmJob(job)));
  }
  return compute(countFilmJob, job);
}

/// Counts a drop-plate photo with its layout off the UI thread (in a Web Worker on browsers).
Future<DropPlateResult> countDropPlateInBackground(DropJob job) async {
  if (kIsWeb) {
    return readDrop(await runPhotoJob(job.$1, dropJob(job)));
  }
  return compute(countDropPlateInPhoto, job);
}

Future<ZoneResult> measureZonesInBackground(
  (Uint8List, ZoneOptions) job,
) async {
  if (kIsWeb) return readZones(await runPhotoJob(job.$1, zoneJob(job.$2)));
  return compute(measureZonesInPhoto, job);
}

Future<PlateLabel?> readLabelInBackground(Uint8List bytes) async {
  if (!kIsWeb) return compute(readLabelFromPhoto, bytes);
  final result = await runPhotoJob(bytes, {'kind': 'label'});
  return PlateLabel.parse(result['label'] as String? ?? '');
}

Future<Uint8List> annotateInBackground(AnnotationJob job) async {
  if (!kIsWeb) return compute(annotatePhoto, job);
  final result = await runPhotoJob(job.photo, annotationJob(job));
  return result['binary'] as Uint8List;
}

Future<PlatesInPhoto> findPlatesInBackground(
  (Uint8List, PlateFormat) job,
) async {
  if (!kIsWeb) return compute(findPlatesInPhoto, job);
  final r = await runPhotoJob(job.$1, {
    'kind': 'find_plates',
    'format': job.$2.name,
  });
  return PlatesInPhoto(
    [for (final p in r['plates'] as List) Plate.fromJson(object(p))],
    r['width'] as int,
    r['height'] as int,
    otherSizes: r['other_sizes'] as bool? ?? false,
  );
}

Future<(Uint8List, Plate)> cropPlateInBackground((Uint8List, Plate) job) async {
  if (!kIsWeb) return compute(cropToPlate, job);
  final r = await runPhotoJob(job.$1, {
    'kind': 'crop',
    'plate': job.$2.toJson(),
  });
  return (r['binary'] as Uint8List, Plate.fromJson(object(r['plate'])));
}
