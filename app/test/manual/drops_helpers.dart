// Helpers for the drop-plate and film chapters: point at a place on the
// plate photo (a drop, a colony, a grid square), which has no widget of its
// own for the harness to find.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

final _spots = <OverlayEntry>[];

/// The review screen's photo: its local coordinates are image pixels.
Finder get photoArea => find.byWidgetPredicate(
  (w) => w is GestureDetector && w.onLongPressStart != null,
);

/// Image pixel [px] of the review photo on the screen.
Offset onPhoto(Manual m, Offset px) =>
    m.tester.renderObject<RenderBox>(photoArea).localToGlobal(px);

/// An invisible box over [rect] (screen coordinates) for a callout.
Finder screenBox(Manual m, Rect rect) {
  final key = UniqueKey();
  final entry = OverlayEntry(
    builder: (_) => Positioned.fromRect(
      rect: rect,
      child: IgnorePointer(child: SizedBox(key: key)),
    ),
  );
  m.navigator.overlay!.insert(entry);
  _spots.add(entry);
  return find.byKey(key);
}

/// A box around a circle of [radius] image pixels at [px] on the photo.
Finder photoSpot(Manual m, Offset px, double radius) {
  final a = onPhoto(m, px - Offset(radius, radius));
  final b = onPhoto(m, px + Offset(radius, radius));
  return screenBox(m, Rect.fromPoints(a, b));
}

/// Removes the boxes made by [screenBox] and [photoSpot].
Future<void> clearSpots(Manual m) async {
  for (final e in _spots) {
    e
      ..remove()
      ..dispose();
  }
  _spots.clear();
  await m.tester.pump();
}

/// Taps image pixel [px] of the review photo.
Future<void> tapPhoto(Manual m, Offset px) async {
  await m.tester.tapAt(onPhoto(m, px));
  await m.settle();
}

/// Drags what is at image pixel [from] of the review photo to [to].
///
/// The photo's pan starts where the finger has passed the pan slop, and
/// that is where the app looks for a drop, so the finger starts one slop
/// above [from].
Future<void> dragOnPhoto(Manual m, Offset from, Offset to) async {
  const slop = Offset(0, kPanSlop + 1);
  final g = await m.tester.startGesture(onPhoto(m, from) - slop);
  await g.moveBy(slop);
  await m.tester.pump();
  await g.moveTo(onPhoto(m, to));
  await m.tester.pump();
  await g.up();
  await m.settle();
}

/// The whole text field or dropdown around its [label] (it has no InkWell
/// for the harness to outline).
Finder field(Finder label) =>
    find.ancestor(of: label, matching: find.byType(InputDecorator)).first;

/// Scrolls [f] into view, [alignment] of the way down the screen. [up]:
/// it is above the current view and may not be built yet.
Future<void> showAt(
  Manual m,
  Finder f, {
  double alignment = 0.3,
  bool up = false,
}) async {
  if (f.evaluate().isEmpty) {
    await m.tester.scrollUntilVisible(
      f,
      up ? -200 : 200,
      scrollable: find.byType(Scrollable).first,
    );
  }
  final done = Scrollable.ensureVisible(
    m.tester.element(f.first),
    alignment: alignment,
  );
  await m.tester.pumpAndSettle();
  await done;
}
