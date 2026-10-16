import 'package:colony_counter/app_info.dart';
import 'package:colony_counter/core/calculator.dart';
import 'package:colony_counter/core/plate.dart';
import 'package:colony_counter/l10n/l10n.dart';
import 'package:colony_counter/l10n/labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'count_helpers.dart';
import 'harness.dart';

void main() {
  chapter('start', (m) async {
    await m.start(
      seed: (store) async {
        await seedPlate(
          store,
          'medium.jpg',
          sampleId: 'Milk A',
          dilutionExp: 4,
          age: const Duration(hours: 2),
        );
        await seedPlate(
          store,
          'sparse.jpg',
          sampleId: 'Milk A',
          dilutionExp: 5,
        );
      },
    );
    final t = m.tester;
    Finder tab(String label) => find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text(label),
    );

    // --- The four tabs ----------------------------------------------------
    await m.shot('1-plates', [
      (tab(tr.homePlates), Mark.tap),
      (await exactly(m, find.byType(ListTile).first), Mark.look),
      (find.text(tr.homeCountPlate), Mark.tap),
    ]);
    await clearPins(m);
    await m.shot('2-plates-tools', [
      (tipIcon(tr.homeSeveralPlates), Mark.tap),
      (tipIcon(tr.homeImportPhoto), Mark.tap),
    ]);
    await m.tap(tab(tr.homeSamples));
    await m.shot('3-samples', [
      (tab(tr.homeSamples), Mark.tap),
      (find.text(tr.homeNewSample), Mark.tap),
      (tipIcon(tr.homeScanLabel), Mark.tap),
    ]);
    await m.tap(tab(tr.homeCompare));
    await m.shot('4-compare', [
      (tab(tr.homeCompare), Mark.tap),
      (
        await around(
          m,
          find.text(tr.compareEmpty),
          const EdgeInsets.only(top: 22),
        ),
        Mark.look,
      ),
    ]);
    await clearPins(m);
    await m.tap(tab(tr.homeZones));
    await m.shot('5-zones', [
      (tab(tr.homeZones), Mark.tap),
      (find.text(tr.zonesMeasure), Mark.tap),
    ]);
    await m.tap(tab(tr.homePlates));

    // --- The ⋮ menu -------------------------------------------------------
    final menu = find.byIcon(Icons.more_vert);
    await m.tap(menu);
    await m.shot('6-menu', [
      (find.text(tr.homeExportCsv), Mark.tap),
      (find.text(tr.homeBackUpAll), Mark.tap),
      (find.text(tr.homeRestore), Mark.tap),
    ]);
    await m.shot('7-menu-more', [
      (find.text(tr.accuracyTitle), Mark.tap),
      (find.text(tr.homeExportTraining), Mark.tap),
      (find.text(tr.homeSettings), Mark.tap),
    ]);

    // --- Settings ---------------------------------------------------------
    await m.tap(find.text(tr.homeSettings));
    await m.shot('8-settings', [
      (find.text('ไทย'), Mark.tap),
      (find.text(tr.themeLight), Mark.tap),
    ]);
    await m.tap(find.text(tr.themeDark));
    await m.shot('9-dark', [(find.text(tr.themeDark), Mark.tap)]);
    await m.tap(find.text(tr.themeLight));
    await m.show(find.byType(DropdownButtonFormField<PlateFormat>));
    await m.shot('10-defaults', [
      (find.text(CountingRule.spreadRules[1].text), Mark.tap),
      (find.text('0.2 mL'), Mark.tap),
      (await exactly(m, find.byIcon(Icons.arrow_drop_down)), Mark.tap),
    ]);
    await clearPins(m);
    await m.tap(find.byType(DropdownButtonFormField<PlateFormat>));
    await m.shot('11-plate-type', [
      (find.text(PlateFormat.dish90.text).last, Mark.tap),
    ]);
    await m.tap(find.text(PlateFormat.dish90.text).last);
    await m.back();

    // --- Counting accuracy ------------------------------------------------
    await m.tap(menu);
    await m.tap(find.text(tr.accuracyTitle));
    await m.shot('12-accuracy', [
      (
        find.ancestor(
          of: find.text(tr.accuracyNoChecked),
          matching: find.byType(Card),
        ),
        Mark.look,
      ),
      (find.text(tr.accuracyEvery(10)), Mark.tap),
    ]);
    await clearPins(m);
    await m.back();

    // --- About ------------------------------------------------------------
    await m.tap(menu);
    await m.shot('13-menu-about', [(find.text(tr.aboutTitle), Mark.tap)]);
    await m.tap(find.text(tr.aboutTitle));
    await m.shot('14-about', [
      (find.textContaining(kAppVersion), Mark.look),
      (find.text(tr.aboutEmail), Mark.tap),
    ]);
    await t.scrollUntilVisible(
      find.text(tr.aboutIntendedUse),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await m.settle();
    await m.shot('15-about-more', [
      (find.text(tr.aboutOpenSource), Mark.tap),
      (_tile(tr.aboutPrivacy), Mark.look),
      (_tile(tr.aboutIntendedUse), Mark.look),
    ]);
  });
}

Finder _tile(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(ListTile));
