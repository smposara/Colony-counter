// Helpers for the `count` manual chapter (also used by `start`).

import 'package:colony_counter/core/background.dart';
import 'package:colony_counter/core/pipeline.dart';
import 'package:colony_counter/data/plate_record.dart';
import 'package:colony_counter/data/plate_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

var _seeded = 0;

/// Counts [name] (a test fixture) and saves it as a plate, as if counted in
/// the app. Call inside `m.start(seed: ...)`.
Future<PlateRecord> seedPlate(
  PlateStore store,
  String name, {
  String sampleId = '',
  int dilutionExp = 0,
  bool verified = false,
  Duration age = Duration.zero,
}) async {
  final photo = fixture(name);
  final res = await countPhotoInBackground(photo, const CountOptions());
  final id = 'seed${_seeded++}';
  return store.saveCapture(
    PlateRecord(
      id: id,
      createdAt: DateTime.now().subtract(age),
      imagePath: '',
      imageWidth: res.imageWidth,
      imageHeight: res.imageHeight,
      plate: res.plate,
      colonies: res.colonies,
      autoCount: res.count,
      flags: res.flags,
      sampleId: sampleId,
      dilutionExp: dilutionExp,
      verified: verified,
    ),
    photo,
  );
}

final _pins = <OverlayEntry>[];

/// An invisible box at screen point [at], for marking a spot on the photo
/// (a colony, empty agar) that has no widget of its own. Remove with
/// [clearPins] after the shot.
Future<Finder> pin(Manual m, Offset at, {double size = 30}) =>
    box(m, Rect.fromCenter(center: at, width: size, height: size));

/// An invisible box over [f] grown by [grow], so a callout's badge sits
/// beside the text it points at rather than on it.
Future<Finder> around(Manual m, Finder f, EdgeInsets grow) {
  final r = m.tester.getRect(f.first);
  return box(
    m,
    Rect.fromLTRB(
      r.left - grow.left,
      r.top - grow.top,
      r.right + grow.right,
      r.bottom + grow.bottom,
    ),
  );
}

/// [f] itself, as a box the harness can outline as a tap or text entry (it
/// only outlines a tap on a widget inside an InkWell: not a text field).
Future<Finder> exactly(Manual m, Finder f) => around(m, f, EdgeInsets.zero);

/// An invisible box [by] inside [f]: keeps the badge of a callout on a big
/// area (the photo) off the bars around it.
Future<Finder> inside(Manual m, Finder f, double by) =>
    box(m, m.tester.getRect(f.first).deflate(by));

/// An invisible box at screen rectangle [r] to mark.
Future<Finder> box(Manual m, Rect r) async {
  final key = UniqueKey();
  final entry = OverlayEntry(
    builder: (_) => Positioned.fromRect(
      rect: r,
      child: IgnorePointer(
        // An InkWell, so that the harness outlines this box.
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(child: SizedBox.expand(key: key)),
        ),
      ),
    ),
  );
  m.tester.state<OverlayState>(find.byType(Overlay).first).insert(entry);
  _pins.add(entry);
  await m.tester.pump();
  return find.byKey(key);
}

Future<void> clearPins(Manual m) async {
  for (final e in _pins) {
    e.remove();
  }
  _pins.clear();
  await m.tester.pump();
}

/// The plate photo on the review screen.
Finder get platePhoto => find.byType(Image).first;

/// Screen position of image pixel [p] on the review screen's photo (after
/// any zoom).
Offset onPhoto(Manual m, Offset p, {int imageWidth = 1000}) {
  final r = m.tester.getRect(platePhoto);
  final k = r.width / imageWidth;
  return r.topLeft + p * k;
}

/// Two-finger zoom by [scale] around screen point [c].
Future<void> pinch(Manual m, Offset c, double scale) async {
  const d = 30.0;
  final a = await m.tester.startGesture(c - const Offset(d, 0));
  final b = await m.tester.startGesture(c + const Offset(d, 0), pointer: 7);
  const steps = 12;
  for (var i = 1; i <= steps; i++) {
    final s = d * (1 + (scale - 1) * i / steps);
    await a.moveTo(c - Offset(s, 0));
    await b.moveTo(c + Offset(s, 0));
    await m.tester.pump(const Duration(milliseconds: 16));
  }
  await a.up();
  await b.up();
  await m.settle();
}

/// The review screen's count ("114 CFU").
Finder get countValue =>
    find.ancestor(of: find.text('CFU'), matching: find.byType(Row)).first;

/// An icon button by its tooltip, findable by the harness's outline (a
/// tooltip sits outside its button's ink).
Finder tipIcon(String tooltip) => find
    .descendant(of: find.byTooltip(tooltip), matching: find.byType(Icon))
    .first;
