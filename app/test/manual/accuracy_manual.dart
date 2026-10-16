import 'dart:math' as math;

import 'package:colony_counter/data/accuracy.dart';
import 'package:colony_counter/l10n/l10n.dart';
import 'package:colony_counter/ui/format.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'data_helpers.dart';
import 'harness.dart';

Finder _card(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(Card)).first;

/// A summary figure: its value and its label.
Finder _stat(String label) => find
    .ancestor(of: find.text(label).first, matching: find.byType(Column))
    .first;

Future<void> _scrollTo(Manual m, Finder f) async {
  await m.tester.scrollUntilVisible(
    f,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await m.show(f);
}

/// Taps the dot of the checked plate with the largest error; returns the
/// detail line that appears under the chart.
Future<Finder> _tapWorstDot(Manual m) async {
  final pts = AccuracyReport(m.store.records).points;
  final worst = pts.reduce((a, b) => a.error.abs() >= b.error.abs() ? a : b);
  // Same axes as the chart (accuracy_screen.dart _ScatterPainter).
  final top = pts.fold(10, (a, p) => math.max(a, math.max(p.auto, p.checked)));
  final v = top * 1.05;
  final e = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
  final max = [1, 2, 2.5, 5, 10].map((k) => k * e).firstWhere((x) => x >= v);
  final box = m.tester.getRect(
    find
        .descendant(
          of: _card(tr.accuracyScatterTitle),
          matching: find.byType(CustomPaint),
        )
        .last,
  );
  await m.tester.tapAt(
    Offset(
      box.left + 36 + worst.checked / max * (box.width - 44),
      box.top + 8 + (1 - worst.auto / max) * (box.height - 36),
    ),
  );
  await m.settle();
  return find.textContaining(plateLabel(worst.record)).first;
}

void main() {
  chapter('accuracy', (m) async {
    // Nine plates since the last checked one: the tenth asks for a check.
    await m.start(seed: seedAccuracy);
    nextPhoto = fixture('medium.jpg');
    await m.tap(find.text(tr.homeCountPlate));
    await m.shot('1-prompt', [
      (find.text(tr.reviewAccuracyCheck), Mark.look),
      (find.text(tr.reviewModeEdit), Mark.tap),
      (find.text(tr.reviewSavePlate), Mark.tap),
    ]);

    await m.tap(find.text(tr.reviewSavePlate));
    final verified = find.text(tr.saveSheetVerified);
    await m.show(verified);
    await m.tap(verified);
    final save = find.descendant(
      of: find.byType(FilledButton),
      matching: find.text(tr.saveSheetSave),
    );
    await m.show(save);
    await m.shot('2-checked', [(verified, Mark.tap), (save, Mark.tap)]);
    await m.tap(save);

    // Plates tab → ⋮ → Counting accuracy.
    await m.tap(find.byType(PopupMenuButton<String>));
    await m.shot('3-menu', [(find.text(tr.accuracyTitle), Mark.tap)]);
    await m.tap(find.text(tr.accuracyTitle));
    await m.shot('4-summary', [
      (find.textContaining('±10').first, Mark.look),
      (_stat(tr.accuracyMeanError), Mark.look),
      (_stat(tr.accuracyBias), Mark.look),
    ]);

    final scatter = _card(tr.accuracyScatterTitle);
    await m.show(scatter);
    final detail = await _tapWorstDot(m);
    await m.shot('5-chart', [
      (
        find.descendant(of: scatter, matching: find.byType(AspectRatio)),
        Mark.look,
      ),
      (detail, Mark.look),
    ]);

    final errors = _card(tr.accuracyErrorsTitle);
    await m.show(errors);
    final tile = find.descendant(
      of: find.byType(ListTile).first,
      matching: find.byType(Text),
    );
    await m.shot('6-errors', [
      (find.text(tr.accuracyRangeColonies('30–300')), Mark.look),
      (find.text(tr.homeFlagged).last, Mark.look),
      (tile.first, Mark.tap),
    ]);

    await _scrollTo(m, find.text(tr.accuracyEvery(10)));
    await m.shot('7-every', [(find.byType(SegmentedButton<int>), Mark.look)]);
  });
}
