import '../core/timelapse.dart';
import 'plate_record.dart';
import 'plate_store.dart';

/// The photos of one time-lapse series, oldest first.
List<PlateRecord> seriesPhotos(PlateStore store, String seriesId) {
  final photos = [
    for (final r in store.records)
      if (r.seriesId == seriesId) r,
  ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  return photos;
}

/// Hours for each photo: its incubation time when every photo has one,
/// otherwise hours since the first photo (plus the first photo's incubation
/// time, if known).
List<double> seriesHours(List<PlateRecord> photos) {
  if (photos.isEmpty) return const [];
  if (photos.every((p) => p.incubationH != null)) {
    return [for (final p in photos) p.incubationH!];
  }
  final first = photos.first;
  final h0 = first.incubationH ?? 0;
  return [
    for (final p in photos)
      h0 + p.createdAt.difference(first.createdAt).inMinutes / 60,
  ];
}

TimelapseResult analyseSeries(List<PlateRecord> photos) {
  final hours = seriesHours(photos);
  return analyseTimelapse([
    for (var i = 0; i < photos.length; i++)
      TimelapseFrame(hours[i], photos[i].plate, photos[i].colonies),
  ]);
}

String _csvCell(Object? v) => v == null ? '' : '$v';

/// One row per colony of the last photo: where it is, when it appeared and
/// its diameter in each photo.
String timelapseCsv(TimelapseResult res) {
  final hours = [for (final f in res.frames) f.hours];
  double r3(double v) => (v * 1000).round() / 1000;
  final head = [
    'colony',
    'x_mm',
    'y_mm',
    'appeared_h',
    'growth_mm_per_h',
    for (final h in hours) 'diameter_mm_at_${r3(h)}h',
  ];
  final rows = [head.join(',')];
  for (var i = 0; i < res.tracks.length; i++) {
    final t = res.tracks[i];
    final byH = {for (final (h, d) in t.sizes) h: d};
    rows.add(
      [
        i + 1,
        r3(t.x),
        r3(t.y),
        r3(t.appearedH),
        t.growthMmPerH == null ? null : r3(t.growthMmPerH!),
        for (final h in hours) byH[h] == null ? null : r3(byH[h]!),
      ].map(_csvCell).join(','),
    );
  }
  return '${rows.join('\n')}\n';
}
