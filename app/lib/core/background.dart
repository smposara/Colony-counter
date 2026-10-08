import 'package:flutter/foundation.dart';

import 'drop_layout.dart';
import 'petrifilm.dart';
import 'pipeline.dart';

CountResult _count((Uint8List, CountOptions) job) => countPhoto(job.$1, job.$2);

/// [countPhoto] off the UI thread on phones (a background isolate).
///
/// Browsers have no isolates, so on the web this runs on the main thread after
/// letting one frame paint, so the "Counting…" message is visible meanwhile.
Future<CountResult> countPhotoInBackground(
  Uint8List bytes, [
  CountOptions options = const CountOptions(),
]) async {
  if (kIsWeb) {
    await Future<void>.delayed(const Duration(milliseconds: 60));
    return countPhoto(bytes, options);
  }
  return compute(_count, (bytes, options));
}

/// Counts a dry-film photo off the UI thread (on the web, after a frame so
/// the progress indicator shows).
Future<FilmResult> countFilmInBackground(FilmJob job) async {
  if (kIsWeb) {
    await Future<void>.delayed(const Duration(milliseconds: 60));
    return countFilmJob(job);
  }
  return compute(countFilmJob, job);
}

/// Counts a drop-plate photo with its layout off the UI thread (on the web,
/// after a frame so the progress indicator shows).
Future<DropPlateResult> countDropPlateInBackground(DropJob job) async {
  if (kIsWeb) {
    await Future<void>.delayed(const Duration(milliseconds: 60));
    return countDropPlateInPhoto(job);
  }
  return compute(countDropPlateInPhoto, job);
}
