// Helpers for the zone chapters (zones_manual.dart, calibration_manual.dart).

import 'dart:math' as math;

import 'package:colony_counter/core/zones.dart';
import 'package:colony_counter/data/plate_store.dart';
import 'package:colony_counter/data/zone_record.dart';
import 'package:colony_counter/ui/zone_review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

/// Test-item labels for the plate in zones_reflected.jpg, clockwise from
/// 12 o'clock (the top disk has no zone: the negative control).
const kZoneLabels = ['Neg', 'Ext A', 'Amp 10', 'Ext B', 'Ext C', 'Ext D'];

final _spots = <OverlayEntry>[];

/// An invisible box at [rect] (screen points), to point a callout at a place
/// on the photo rather than at a widget. Cleared by [clearSpots].
Future<Finder> spot(Manual m, Rect rect) async {
  final key = UniqueKey();
  final entry = OverlayEntry(
    builder: (_) => Positioned.fromRect(
      rect: rect,
      // An InkWell, so the harness outlines it like a button; it paints
      // nothing and takes no touches.
      child: IgnorePointer(
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(onTap: null, child: SizedBox.expand(key: key)),
        ),
      ),
    ),
  );
  m.navigator.overlay!.insert(entry);
  _spots.add(entry);
  await m.tester.pump();
  return find.byKey(key);
}

Future<void> clearSpots(Manual m) async {
  for (final e in _spots) {
    e.remove();
  }
  _spots.clear();
  await m.tester.pump();
}

/// [Manual.shot], but a tap, hold or type mark on something that is not
/// inside a button (a text field, a dropdown's label) still gets an outline
/// of its own size: the harness would otherwise find no control to outline.
Future<void> snap(Manual m, String name, List<(Finder, Mark)> marks) async {
  final out = <(Finder, Mark)>[];
  for (final (f, k) in marks) {
    expect(f, findsWidgets, reason: '${m.chapter}/$name: $f');
    final inButton =
        k == Mark.look || k == Mark.drag || _hasControl(m, f.first);
    out.add((inButton ? f : await spot(m, m.tester.getRect(f.first)), k));
  }
  await m.shot(name, out);
  await clearSpots(m);
}

bool _hasControl(Manual m, Finder f) => find
    .ancestor(
      of: f,
      matching: find.byWidgetPredicate(
        (w) =>
            w is InkWell ||
            w is InkResponse ||
            w is FloatingActionButton ||
            w is NavigationDestination,
      ),
    )
    .evaluate()
    .isNotEmpty;

/// What the zone review screen draws over the photo.
ZoneOverlayPainter reviewPainter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((c) => c.painter)
    .whereType<ZoneOverlayPainter>()
    .single;

/// The marks drawn on the zone review screen.
List<ZoneMark> reviewMarks(WidgetTester tester) => reviewPainter(tester).marks;

/// Photo pixels to screen points on the zone review screen.
Offset Function(double, double) photoToScreen(
  WidgetTester tester,
  int imageWidth,
) {
  final rect = tester.getRect(find.byKey(const ValueKey('zonePhoto')));
  final k = rect.width / imageWidth;
  return (x, y) => rect.topLeft + Offset(x * k, y * k);
}

/// A square of [size] screen points centred on [c].
Rect around(Offset c, [double size = 30]) =>
    Rect.fromCenter(center: c, width: size, height: size);

/// Saves more replicate plates like [first] (same experiment, organism and
/// labels), each zone a little different, as if measured on other plates.
Future<void> addReplicates(
  Manual m,
  ZoneRecord first,
  List<int> replicates,
) async {
  final rnd = math.Random(7);
  await m.tester.runAsync(() async {
    for (final rep in replicates) {
      final id = '${first.id}_r$rep';
      final name = await m.store.savePhoto(fixture('zones_reflected.jpg'), id);
      final marks = [
        for (final z in first.marks)
          z.noZone
              ? z
              : () {
                  final mm = z.diameterMm + (rnd.nextDouble() - 0.5) * 1.6;
                  return z.copyWith(
                    diameterMm: mm,
                    radiusPx: mm / 2 / first.mmPerPx,
                    opened: true,
                  );
                }(),
      ];
      await m.store.upsertZone(
        ZoneRecord.fromJson({
          ...first.toJson(),
          'id': id,
          'image': name,
          'replicate': rep,
          'created_at': first.createdAt
              .add(Duration(minutes: rep))
              .toIso8601String(),
          'marks': [for (final z in marks) z.toJson()],
        }),
      );
    }
  });
  await m.settle();
}

/// A plate measured from [photo] and saved, as if photographed [ago].
Future<ZoneRecord> seedZonePlate(
  PlateStore store, {
  String photo = 'zones_reflected.jpg',
  String id = 'p1',
  String experiment = '',
  Duration ago = Duration.zero,
}) async {
  final bytes = fixture(photo);
  final res = measureZonesInPhoto((bytes, const ZoneOptions()));
  final name = await store.savePhoto(bytes, 'zone_$id');
  final r = ZoneRecord.fromResult(
    res,
    id: id,
    imagePath: name,
    createdAt: DateTime.now().subtract(ago),
    experiment: experiment,
    camera: '0',
  );
  await store.upsertZone(r);
  return r;
}
