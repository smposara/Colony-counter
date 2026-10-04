import 'package:flutter/foundation.dart';

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
