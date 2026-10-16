// Seed data for the accuracy and data chapters: real counts of the fixture
// photos, saved as plates (some checked colony by colony).

import 'package:colony_counter/core/classical.dart';
import 'package:colony_counter/core/pipeline.dart';
import 'package:colony_counter/data/plate_record.dart';
import 'package:colony_counter/data/plate_store.dart';

import 'harness.dart';

final _counts = <String, CountResult>{};

CountResult _count(String photo) =>
    _counts[photo] ??= countPhoto(fixture(photo));

/// Saves a plate of [photo] counted by the app, then corrected by hand:
/// [missed] colonies added, [extra] automatic marks removed. [keep] < 1
/// keeps only that share of the detections, for a spread of counts.
Future<void> seedPlate(
  PlateStore store, {
  required String id,
  required String photo,
  required DateTime at,
  String sample = 'S1',
  int dilution = 4,
  int replicate = 1,
  int missed = 0,
  int extra = 0,
  double keep = 1,
  bool verified = false,
  List<String> flags = const [],
}) async {
  final r = _count(photo);
  final path = await store.savePhoto(fixture(photo), id);
  final auto = r.colonies.sublist(0, (r.colonies.length * keep).round());
  final kept = auto.sublist(0, auto.length - extra.clamp(0, auto.length));
  final removed = auto.sublist(kept.length);
  final added = [
    for (var i = 0; i < missed; i++)
      Colony(
        r.plate.cx + (i % 7 - 3) * r.plate.radius * 0.2,
        r.plate.cy + (i ~/ 7 - 3) * r.plate.radius * 0.2,
        6,
        manual: true,
      ),
  ];
  await store.upsert(
    PlateRecord(
      id: id,
      createdAt: at,
      imagePath: path,
      imageWidth: r.imageWidth,
      imageHeight: r.imageHeight,
      plate: r.plate,
      colonies: [...kept, ...added],
      rejected: removed,
      autoCount: auto.fold(0, (s, c) => s + c.n),
      flags: {...r.flags, ...flags}.toList(),
      sampleId: sample,
      dilutionExp: dilution,
      replicate: replicate,
      guided: true,
      verified: verified,
    ),
  );
}

const _photos = ['medium.jpg', 'sparse.jpg', 'backlit.jpg', 'dense.jpg'];

/// 15 checked plates (older) and [recent] unchecked ones after them.
Future<void> seedAccuracy(PlateStore store, {int recent = 9}) async {
  // (missed, extra, flagged, keep) per checked plate: mostly close, a few
  // off.
  const checks = [
    (3, 0, false, 1.0),
    (0, 2, false, 0.5),
    (4, 0, false, 1.0),
    (12, 0, false, 1.0),
    (14, 0, true, 0.7),
    (0, 0, false, 0.6),
    (3, 1, false, 0.6),
    (40, 0, true, 1.0),
    (2, 0, false, 0.5),
    (0, 6, true, 1.0),
    (6, 0, false, 1.0),
    (5, 3, false, 0.75),
    (0, 14, true, 1.0),
    (5, 0, false, 0.3),
    (1, 1, false, 0.8),
  ];
  final start = DateTime(2026, 9, 1, 9);
  for (final (i, (missed, extra, flagged, keep)) in checks.indexed) {
    await seedPlate(
      store,
      id: 'chk$i',
      photo: _photos[i % _photos.length],
      at: start.add(Duration(days: i, hours: i % 3)),
      sample: 'S${i ~/ 3 + 1}',
      dilution: 4 + i % 3,
      replicate: 1 + i % 2,
      missed: missed,
      extra: extra,
      keep: keep,
      verified: true,
      flags: flagged ? const ['many_clusters'] : const [],
    );
  }
  for (var i = 0; i < recent; i++) {
    await seedPlate(
      store,
      id: 'new$i',
      photo: _photos[(i + 1) % _photos.length],
      at: DateTime(2026, 10, 1, 9).add(Duration(days: i)),
      sample: 'S${6 + i ~/ 3}',
      dilution: 4 + i % 3,
      missed: i % 3,
    );
  }
}
