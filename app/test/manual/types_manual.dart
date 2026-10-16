import 'package:colony_counter/l10n/l10n.dart';
import 'package:colony_counter/ui/photo_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../synth.dart';
import 'harness.dart';
import 'types_helpers.dart';

/// A 100 mm square plate and a 47 mm gridded membrane filter, in portrait.
final _square = synthPhoto(1200, 1600, [
  SynthPlate(600, 800, 440, square: true, sizeMm: 100, colonies: 70),
], seed: 5);
final _membrane = synthPhoto(1200, 1600, [
  SynthPlate(
    600,
    800,
    440,
    membrane: true,
    sizeMm: 47,
    colonyMm: 1.0,
    colonies: 45,
  ),
], seed: 6);

/// The icon of an app-bar action, so its whole button is outlined.
Finder _icon(String tooltip) =>
    find.descendant(of: find.byTooltip(tooltip), matching: find.byType(Icon));

void main() {
  chapter('types', (m) async {
    await m.start();

    // Settings: the default plate type for quick counts and new samples.
    final more = find.byIcon(Icons.more_vert).first;
    await m.tap(more);
    await m.shot('1-menu', [(find.text(tr.homeSettings), Mark.tap)]);
    await m.tap(find.text(tr.homeSettings));
    final dflt = find.ancestor(
      of: find.text(tr.homeDefaultPlateType),
      matching: find.byWidgetPredicate((w) => w is DropdownButtonFormField),
    );
    await m.show(dflt);
    await m.shot('2-settings', [(dflt, Mark.look)]);
    await m.tap(dflt);
    final square = find.text(tr.formatSquare100).last;
    await m.shot('3-choose', [(square, Mark.tap)]);
    await m.tap(square);
    await m.back();

    // The camera guide turns square.
    final hook = debugTakePlatePhoto;
    debugTakePlatePhoto = null;
    fakeCamera(m.tester, _square);
    await m.tap(find.text(tr.homeCountPlate));
    await m.settle(seconds: 3);
    final guide = find.byWidgetPredicate(
      (w) =>
          w is CustomPaint &&
          w.painter.runtimeType.toString() == '_GuidePainter',
    );
    await m.shot('4-guide', [(guide, Mark.look)]);
    await m.back();
    debugTakePlatePhoto = hook;

    // Counted inside the square.
    nextPhoto = _square;
    await m.tap(find.text(tr.homeCountPlate));
    final plateMode = find.text(tr.reviewModePlate);
    await m.shot('5-square', [(plateMode, Mark.tap)]);
    await m.tap(plateMode);
    await m.shot('6-adjust', [
      (find.byType(Slider).first, Mark.drag),
      (find.byType(Slider).last, Mark.drag),
      (find.text(tr.reviewRecountSquare), Mark.tap),
    ]);
    await m.back();
    await m.tap(find.text(tr.reviewDiscard));

    // A membrane filter: change the plate type in the review menu.
    nextPhoto = _membrane;
    await m.tap(find.text(tr.homeCountPlate));
    await m.tap(_icon(tr.reviewMenuTooltip));
    final item = find.textContaining(
      tr.reviewPlateTypeItem('').replaceAll('…', ''),
    );
    await m.shot('7-review-menu', [(item, Mark.tap)]);
    await m.tap(item);
    final membrane = find.text(tr.formatMembrane47);
    await m.shot('8-types', [(membrane, Mark.tap)]);
    await m.tap(membrane);
    await m.shot('9-membrane', [(find.text(tr.reviewSavePlate), Mark.tap)]);

    // Results per 100 mL.
    await m.tap(find.text(tr.reviewSavePlate));
    final result = find.textContaining('CFU/100 mL');
    await m.show(result);
    await m.shot('10-per-100ml', [
      (find.ancestor(of: result, matching: find.byType(Card)), Mark.look),
    ]);
  });
}
