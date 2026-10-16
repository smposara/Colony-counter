import 'package:colony_counter/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'colours_helpers.dart';
import 'harness.dart';

void main() {
  chapter('colours', (m) async {
    await m.start();
    nextPhoto = blueWhitePlate();
    await m.tap(find.text(tr.homeCountPlate));

    // The review menu holds the colour modes.
    final menu = find.descendant(
      of: find.byTooltip(tr.reviewMenuTooltip),
      matching: find.byType(Icon),
    );
    await m.shot('1-menu', [(menu, Mark.tap)]);
    await m.tap(menu);
    final blueWhite = find.text(tr.reviewColoursItem(tr.colourBlueWhite));
    final two = find.text(tr.reviewColoursItem(tr.colourTwo));
    await m.shot('2-modes', [(blueWhite, Mark.tap), (two, Mark.tap)]);
    await m.tap(blueWhite);

    // Counts per colour and the share of blue colonies.
    final summary = find
        .ancestor(of: find.textContaining('%'), matching: find.byType(Wrap))
        .first;
    final colour = find.text(tr.reviewModeColour);
    await m.shot('3-counts', [(summary, Mark.look), (colour, Mark.tap)]);

    // Colour mode: tap a colony to switch it between the classes.
    await m.tap(colour);
    final hint = find.text(tr.reviewHintColour);
    await m.shot('4-colour-mode', [(hint, Mark.look)]);
    final photo = m.tester.getRect(find.byType(Image).first);
    for (final (x, y) in scatter(60).take(2)) {
      await m.tester.tapAt(
        photo.topLeft +
            Offset(x / kPhotoSize * photo.width, y / kPhotoSize * photo.height),
      );
      await m.tester.pump();
    }
    await m.settle();
    await m.shot('5-switched', [(summary, Mark.look)]);

    // Two colours, e.g. chromogenic agar.
    await m.tap(menu);
    await m.tap(two);
    await m.shot('6-two-colours', [(summary, Mark.look)]);

    // Or set the colours for every plate of a sample.
    await m.back();
    await m.tap(find.text(tr.reviewDiscard));
    await m.tap(find.text(tr.homeSamples));
    await m.tap(find.text(tr.homeNewSample));
    final segments = find.text(tr.colourBlueWhite);
    await m.tester.scrollUntilVisible(
      segments,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await m.tester.drag(find.byType(ListView), const Offset(0, -150));
    await m.settle();
    await m.tap(segments);
    await m.shot('7-sample', [(segments, Mark.tap)]);
  });
}
