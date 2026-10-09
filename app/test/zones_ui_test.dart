import 'dart:io';

import 'package:colony_counter/core/plate.dart';
import 'package:colony_counter/core/zones.dart';
import 'package:colony_counter/data/plate_store.dart';
import 'package:colony_counter/data/storage/storage.dart';
import 'package:colony_counter/data/zone_record.dart';
import 'package:colony_counter/main.dart';
import 'package:colony_counter/ui/home_screen.dart';
import 'package:colony_counter/ui/zone_review_screen.dart';
import 'package:colony_counter/ui/zone_setup_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _settleReal(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 300 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
  }
}

bool _idle() => find.byType(CircularProgressIndicator).evaluate().isEmpty;

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<PlateStore> _store(WidgetTester tester) async {
  final store = PlateStore(MemoryStorage());
  await tester.runAsync(store.load);
  return store;
}

const _setup = ZoneSetup(experiment: 'Extracts', organism: 'S. aureus');

/// Opens the review screen on a fixture photo and waits for the measurement.
Future<PlateStore> _review(
  WidgetTester tester, {
  String fixture = 'zones_reflected',
  ZoneSetup setup = _setup,
  PlateStore? store,
}) async {
  _phone(tester);
  store ??= await _store(tester);
  // Pushed over a home page, as the app does, so saving can pop it.
  await tester.pumpWidget(const MaterialApp(home: Text('home')));
  final photo = File('test/fixtures/$fixture.jpg').readAsBytesSync();
  final s = store;
  tester
      .state<NavigatorState>(find.byType(Navigator))
      .push(
        MaterialPageRoute<ZoneRecord>(
          builder: (_) =>
              ZoneReviewScreen(store: s, photo: photo, setup: setup),
        ),
      );
  // Past the page transition (the first frame keeps the new page offstage).
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await _settleReal(tester, _idle);
  await tester.pumpAndSettle();
  return store;
}

/// Image pixels to screen points on the review screen's photo.
Offset Function(double, double) _toScreen(WidgetTester tester, int imageW) {
  final rect = tester.getRect(find.byKey(const ValueKey('zonePhoto')));
  final k = rect.width / imageW;
  return (x, y) => rect.topLeft + Offset(x * k, y * k);
}

/// Scrolls the row of zone chips to [chip] and taps it.
Future<void> _tapChip(WidgetTester tester, Finder chip) async {
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester, PlateStore store) async {
  await tester.tap(find.text('Save plate'));
  await _settleReal(tester, () => store.zoneRecords.isNotEmpty);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a new plate is measured, labelled, edited and saved', (
    tester,
  ) async {
    final store = await _store(tester);
    await tester.runAsync(
      () => store.savePanel(
        const ZonePanel('Set A', ['DMSO', 'EtOH', 'Hex', 'Aq', 'MeOH', 'Amp']),
      ),
    );
    await _review(
      tester,
      store: store,
      setup: _setup.copyWith(panel: 'Set A', replicate: 2),
    );
    expect(find.text('6 zones'), findsOneWidget);
    // Clockwise from 12 o'clock: the no-zone disk at the top first.
    expect(find.text('DMSO · 6'), findsOneWidget);
    expect(find.text('EtOH · 11'), findsOneWidget);
    expect(find.text('Hex · 17'), findsOneWidget);

    // Open the 17 mm zone, rename it and make it 1 mm larger.
    await _tapChip(tester, find.text('Hex · 17'));
    expect(find.text('Disk 3'), findsOneWidget);
    expect(find.text('Colonies inside the zone.'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('zoneLabel')), 'Hexane');
    await tester.tap(find.byTooltip('1 mm larger'));
    await tester.pump();
    expect(find.text('18 mm'), findsOneWidget);
    expect(find.textContaining('The app measured 17.'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Hexane · 18'), findsOneWidget);

    await _save(tester, store);
    final r = store.zoneRecords.single;
    expect(r.experiment, 'Extracts');
    expect(r.organism, 'S. aureus');
    expect(r.replicate, 2);
    expect(r.panel, 'Set A');
    expect(r.marks, hasLength(6));
    final hex = r.marks[2];
    expect(hex.label, 'Hexane');
    expect(hex.diameterMm, 18);
    expect(hex.radiusPx, closeTo(18 / 2 / r.mmPerPx, 1e-6));
    expect(hex.autoDiameterMm, closeTo(17.07, 0.3));
    expect(hex.edited, isTrue);
    expect(hex.opened, isTrue);
    expect(r.marks[0].noZone, isTrue);
    expect(r.edits, 1);
    expect(r.imagePath, isNotEmpty);
    expect(
      await tester.runAsync(() => store.readPhotoPath(r.imagePath)),
      isNotNull,
    );
  });

  testWidgets('drag a zone edge to resize it; the view still pans', (
    tester,
  ) async {
    await _review(tester);
    // The 11.5 mm zone at (843, 439); drag its right edge 15 mm outwards
    // (30 mm on the diameter; drags start after Flutter's pan slop).
    final toScreen = _toScreen(tester, 1200);
    final m = _marks(tester)[1];
    final mmPerPx = m.diameterMm / (2 * m.radiusPx);
    final from = toScreen(m.x + m.radiusPx, m.y);
    final to = toScreen(m.x + m.radiusPx + 15 / mmPerPx, m.y);
    final g = await tester.startGesture(from);
    for (var i = 1; i <= 10; i++) {
      await g.moveTo(Offset.lerp(from, to, i / 10)!);
      await tester.pump();
    }
    await g.up();
    await tester.pumpAndSettle();
    expect(find.text('2 · 41'), findsOneWidget);

    // A drag away from every edge pans the view instead.
    final pan = toScreen(600, 600);
    await tester.dragFrom(pan, const Offset(-60, 0));
    await tester.pumpAndSettle();
    expect(find.text('2 · 41'), findsOneWidget);
    expect(find.text('5 · 13'), findsOneWidget);

    // Undo puts the zone back.
    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('2 · 11'), findsOneWidget);
  });

  testWidgets('long-press adds a disk the app missed and measures it', (
    tester,
  ) async {
    final store = await _review(tester, fixture: 'zones_reflected');
    expect(find.text('6 zones'), findsOneWidget);
    // Outside the plate: nothing is added.
    await tester.longPressAt(_toScreen(tester, 1200)(40, 40));
    await tester.pumpAndSettle();
    expect(find.text('6 zones'), findsOneWidget);
    // Delete the 8.7 mm disk at (628, 900), then add it back by hand.
    await _tapChip(tester, find.text('4 · 9'));
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('5 zones'), findsOneWidget);

    final toScreen = _toScreen(tester, 1200);
    await tester.longPressAt(toScreen(627.8, 900.3));
    await _settleReal(tester, () => find.text('Disk 4').evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    expect(find.text('Added by hand.'), findsOneWidget);
    expect(find.text('9 mm'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('6 zones'), findsOneWidget);
    expect(find.text('4 · 9'), findsOneWidget);

    await _save(tester, store);
    final added = store.zoneRecords.single.marks[3];
    expect(added.manual, isTrue);
    expect(added.diameterMm, closeTo(8.7, 0.5));
    expect(added.edited, isTrue);
  });

  testWidgets('unsure zones are checked by opening them', (tester) async {
    final store = await _review(tester, fixture: 'zones_backlit_hazy');
    // Five hazy edges; the no-zone disk needs no check.
    expect(find.text('5 to check'), findsOneWidget);
    final chips = find.byWidgetPredicate(
      (w) => w is ActionChip && w.avatar != null,
    );
    while (chips.evaluate().isNotEmpty) {
      await _tapChip(tester, chips.first);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
    }
    expect(find.text('All checked'), findsOneWidget);
    await _save(tester, store);
    expect(store.zoneRecords.single.checked, isTrue);
  });

  testWidgets('wells: the size is the well diameter', (tester) async {
    final store = await _review(
      tester,
      fixture: 'zones_wells',
      setup: _setup.copyWith(assay: ZoneAssay.well, diskMm: 8),
    );
    expect(find.textContaining('Long-press to add a well'), findsOneWidget);
    await _tapChip(tester, find.byType(ActionChip).first);
    expect(find.text('Well 1'), findsOneWidget);
    await tester.tap(find.text('No zone'));
    await tester.pump();
    expect(find.text('Reported as the well size, 8 mm.'), findsOneWidget);
    expect(find.text('8 mm'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await _save(tester, store);
    final r = store.zoneRecords.single;
    expect(r.assay, ZoneAssay.well);
    expect(r.diskMm, 8);
    expect(r.marks.first.reportedMm(8), 8);
  });

  testWidgets('a saved plate reopens, and leaving unsaved edits asks', (
    tester,
  ) async {
    final store = await _review(tester);
    await _save(tester, store);
    final saved = store.zoneRecords.single;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ZoneReviewScreen(store: store, record: saved),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await _settleReal(tester, _idle);
    await tester.pumpAndSettle();
    expect(find.text('Extracts'), findsOneWidget);
    expect(find.text('6 zones'), findsOneWidget);
    expect(find.text('Save changes'), findsOneWidget);

    // Looking at a zone twice without changing it leaves nothing to save.
    for (var k = 0; k < 2; k++) {
      await _tapChip(tester, find.text('3 · 17'));
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
    }
    expect(find.byTooltip('Undo'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.undo))
          .onPressed,
      isNotNull, // the first look marked it as checked
    );

    // An edit, then back: asks before throwing it away.
    await _tapChip(tester, find.text('2 · 11'));
    await tester.tap(find.byTooltip('1 mm smaller'));
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Discard this count?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(
      store.zoneRecords.single.marks[1].diameterMm,
      saved.marks[1].diameterMm,
    );
  });

  testWidgets('fixing the plate circle measures again', (tester) async {
    final store = await _review(tester);
    await tester.tap(find.byTooltip('Fix plate circle'));
    await tester.pumpAndSettle();
    expect(find.text('Measure again'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    await tester.tap(find.text('Measure again'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await _settleReal(tester, _idle);
    await tester.pumpAndSettle();
    expect(find.text('6 zones'), findsOneWidget);
    expect(find.text('Save plate'), findsOneWidget);
    await _save(tester, store);
    expect(store.zoneRecords.single.marks, hasLength(6));
  });

  testWidgets('the setup sheet remembers its choices', (tester) async {
    _phone(tester);
    final store = await _store(tester);
    ZoneSetupChoice? got;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  got = await showZoneSetupSheet(context, store),
              child: const Text('setup'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('setup'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agar wells'));
    await tester.enterText(find.byKey(const ValueKey('zoneSize')), '8');
    await tester.enterText(find.byType(TextField).at(1), 'E. coli');
    await tester.enterText(find.byType(TextField).at(2), 'Wells 1');
    await tester.pump();

    // A new list of labels.
    await tester.tap(find.byTooltip('New label list'));
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    await tester.enterText(
      find.descendant(of: dialog, matching: find.byType(TextField)).at(0),
      'Set B',
    );
    await tester.enterText(
      find.descendant(of: dialog, matching: find.byType(TextField)).at(1),
      'A\nB\n\nC',
    );
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.textContaining('A · B · C'), findsOneWidget);

    await tester.tap(find.text('From gallery'));
    await tester.pumpAndSettle();
    expect(got, isNotNull);
    expect(got!.fromGallery, isTrue);
    final s = got!.setup;
    expect(s.assay, ZoneAssay.well);
    expect(s.diskMm, 8);
    expect(s.organism, 'E. coli');
    expect(s.experiment, 'Wells 1');
    expect(s.panel, 'Set B');
    expect(store.zonePanels.single.labels, ['A', 'B', 'C']);

    // Remembered after a restart.
    final again = PlateStore(store.backend);
    await tester.runAsync(again.load);
    expect(again.zoneSetup.toJson(), s.toJson());

    // A bad size stops the sheet.
    await tester.tap(find.text('setup'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('zoneSize')), '40');
    await tester.pump();
    expect(find.text('Enter 3 to 15 mm'), findsOneWidget);
    final take = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Take photo'),
        matching: find.byWidgetPredicate((w) => w is FilledButton),
      ),
    );
    expect(take.onPressed, isNull);
  });

  test('the next replicate follows the saved ones', () async {
    final store = PlateStore(MemoryStorage());
    await store.load();
    expect(nextZoneReplicate(store, 'E', 'S', fallback: 3), 3);
    for (final rep in [1, 2]) {
      await store.upsertZone(
        ZoneRecord(
          id: 'z$rep',
          createdAt: DateTime(2026, 10, 9, rep),
          imagePath: 'z$rep.jpg',
          imageWidth: 100,
          imageHeight: 100,
          plate: const Plate(50, 50, 45),
          mmPerPx: 1,
          marks: const [],
          experiment: 'E',
          organism: 'S',
          replicate: rep,
        ),
      );
    }
    expect(nextZoneReplicate(store, 'E', 'S'), 3);
    expect(nextZoneReplicate(store, 'E', 'other'), 1);
  });

  testWidgets('the Zones tab lists zone plates', (tester) async {
    _phone(tester);
    final store = await _store(tester);
    await tester.runAsync(
      () => store.upsertZone(
        ZoneRecord(
          id: 'z1',
          createdAt: DateTime(2026, 10, 9),
          imagePath: 'z1.jpg',
          imageWidth: 100,
          imageHeight: 100,
          plate: const Plate(50, 50, 45),
          mmPerPx: 0.1,
          marks: [
            ZoneMark(
              x: 50,
              y: 20,
              diskRadiusPx: 30,
              radiusPx: 90,
              diameterMm: 18,
              autoDiameterMm: 18,
              flags: const ['hazy'],
            ),
          ],
          experiment: 'Extracts',
          organism: 'S. aureus',
          replicate: 2,
        ),
      ),
    );
    await tester.pumpWidget(MaterialApp(home: HomeScreen(store: store)));
    await tester.tap(find.text('Zones').last);
    await tester.pumpAndSettle();
    expect(find.text('Extracts · S. aureus'), findsOneWidget);
    expect(find.textContaining('Rep 2'), findsOneWidget);
    expect(find.text('1 zone'), findsOneWidget);
    expect(find.byTooltip('1 to check'), findsOneWidget);
    expect(find.text('Measure zones'), findsOneWidget);
    // The colony list is untouched.
    await tester.tap(find.text('Plates'));
    await tester.pumpAndSettle();
    expect(find.text('Extracts · S. aureus'), findsNothing);
  });

  testWidgets('an empty Zones tab says how to start', (tester) async {
    _phone(tester);
    final store = await _store(tester);
    await tester.pumpWidget(MaterialApp(home: HomeScreen(store: store)));
    await tester.tap(find.text('Zones').last);
    await tester.pumpAndSettle();
    expect(find.text('No zone plates yet'), findsOneWidget);
    expect(find.text('Zones (beta)'), findsOneWidget);

    // The disclaimer comes first; cancelling it stops there.
    await tester.tap(find.text('Measure zones'));
    await tester.pumpAndSettle();
    expect(find.text('Zone measurement is in beta'), findsOneWidget);
    expect(find.textContaining('does not interpret them'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Paper disks'), findsNothing);
    expect(store.zoneDisclaimerSeen, isFalse);

    await tester.tap(find.text('Measure zones'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('I understand'));
    await tester.pumpAndSettle();
    expect(find.text('Zone plate'), findsOneWidget);
    expect(find.text('Paper disks'), findsOneWidget);
    expect(store.zoneDisclaimerSeen, isTrue);

    // Only once, also after a restart.
    final again = PlateStore(store.backend);
    await tester.runAsync(again.load);
    expect(again.zoneDisclaimerSeen, isTrue);
    await tester.tapAt(const Offset(180, 20));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Measure zones'));
    await tester.pumpAndSettle();
    expect(find.text('Zone measurement is in beta'), findsNothing);
    expect(find.text('Paper disks'), findsOneWidget);
  });
  testWidgets('Thai on a small phone: the Zones screens fit', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920); // 360 × 640
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final store = await _store(tester);
    await tester.runAsync(() => store.setDefaults(language: 'th'));
    await tester.pumpWidget(ColonyCounterApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('โซนยับยั้ง').last);
    await tester.pumpAndSettle();
    expect(find.text('ยังไม่มีเพลตวัดโซนยับยั้ง'), findsOneWidget);
    await tester.tap(find.text('วัดโซนยับยั้ง'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เข้าใจแล้ว'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('หลุมวุ้น'));
    await tester.pumpAndSettle();
    expect(find.text('เส้นผ่านศูนย์กลางหลุม (มม.)'), findsOneWidget);
    await tester.tapAt(const Offset(180, 20)); // close the sheet
    await tester.pumpAndSettle();

    final photo = File('test/fixtures/zones_reflected.jpg').readAsBytesSync();
    tester
        .state<NavigatorState>(find.byType(Navigator).first)
        .push(
          MaterialPageRoute<ZoneRecord>(
            builder: (_) =>
                ZoneReviewScreen(store: store, photo: photo, setup: _setup),
          ),
        );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await _settleReal(tester, _idle);
    await tester.pumpAndSettle();
    expect(find.text('6 โซน'), findsOneWidget);
    await _tapChip(tester, find.byType(ActionChip).at(2));
    expect(find.text('แผ่นที่ 3'), findsOneWidget);
    expect(find.text('มีโคโลนีในโซน'), findsOneWidget);
  });
}

/// The marks as drawn on the review screen.
List<ZoneMark> _marks(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((c) => c.painter)
    .whereType<ZoneOverlayPainter>()
    .single
    .marks;
