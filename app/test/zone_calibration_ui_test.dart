import 'dart:io';

import 'package:colony_counter/core/zone_calibration.dart';
import 'package:colony_counter/core/zones.dart';
import 'package:colony_counter/data/plate_store.dart';
import 'package:colony_counter/data/storage/storage.dart';
import 'package:colony_counter/data/zone_calibration_record.dart';
import 'package:colony_counter/data/zone_record.dart';
import 'package:colony_counter/main.dart';
import 'package:colony_counter/ui/home_screen.dart';
import 'package:colony_counter/ui/zone_calibration_screen.dart';
import 'package:colony_counter/ui/zone_review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _photo = File('test/fixtures/zones_reflected.jpg').readAsBytesSync();
final _measured = measureZonesInPhoto((_photo, const ZoneOptions()));

Future<void> _settleReal(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 300 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
  }
}

void _phone(WidgetTester tester, {bool small = false}) {
  tester.view.physicalSize = Size(1080, small ? 1920 : 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// A store with a zone plate measured today from the fixture photo.
Future<(PlateStore, ZoneRecord)> _withPlate(WidgetTester tester) async {
  final store = PlateStore(MemoryStorage());
  late ZoneRecord r;
  await tester.runAsync(() async {
    await store.load();
    final name = await store.savePhoto(_photo, 'zone_p1');
    r = ZoneRecord.fromResult(
      _measured,
      id: 'p1',
      imagePath: name,
      createdAt: DateTime.now(),
      experiment: 'Extracts',
      camera: '0',
    );
    await store.upsertZone(r);
  });
  return (store, r);
}

Future<void> _openWizard(WidgetTester tester, PlateStore store) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => openZoneCalibration(context, store, wizard: true),
          child: const Text('go'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
}

Future<void> _useRecent(WidgetTester tester, [String name = 'Extracts']) async {
  tester
      .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
      .removeCurrentSnackBar();
  await tester.pumpAndSettle();
  final b = find.text('Use a plate I just measured');
  await tester.ensureVisible(b);
  await tester.pumpAndSettle();
  await tester.tap(b);
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining('$name ·'));
  await _settleReal(
    tester,
    () => find.text('Scale check').evaluate().isNotEmpty,
  );
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, Key key, String text) async {
  final f = find.byKey(key);
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.enterText(f, text);
  await tester.pump();
}

/// The span and every zone, the readings [offset] mm below the app's.
Future<void> _fill(
  WidgetTester tester,
  ZoneRecord r, {
  double offset = 0.3,
  double spanScale = 1,
}) async {
  final span = recordSpanMm(r, spanPair(r)!) * spanScale;
  await _type(tester, const ValueKey('calSpan'), span.toStringAsFixed(1));
  for (var i = 0; i < r.marks.length; i++) {
    // The plate has 5 clear zones and a disk with no zone (left out by
    // default); tick it so there are the 6 a calliper needs.
    final box = find.byKey(ValueKey('calInclude$i'));
    if (tester.widget<Checkbox>(box).value != true) {
      await tester.ensureVisible(box);
      await tester.pumpAndSettle();
      await tester.tap(box);
      await tester.pump();
    }
    final v = r.marks[i].reportedMm(r.diskMm) - offset;
    await _type(tester, ValueKey('calZone$i'), v.toStringAsFixed(1));
  }
}

Future<void> _seeResult(WidgetTester tester) async {
  // A message from the last try would cover the button.
  tester
      .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
      .removeCurrentSnackBar();
  await tester.pumpAndSettle();
  final b = find.byKey(const ValueKey('calSeeResult'));
  await tester.ensureVisible(b);
  await tester.pumpAndSettle();
  await tester.tap(b);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a used plate: readings → good → saved with the plate', (
    tester,
  ) async {
    _phone(tester);
    final (store, r) = await _withPlate(tester);
    await _openWizard(tester, store);
    expect(find.text('Check the app against your calliper'), findsOneWidget);
    await _useRecent(tester);
    // Numbers only: the app's sizes are hidden while reading.
    expect(find.textContaining('The app\'s sizes are hidden'), findsOneWidget);
    expect(find.textContaining('to the outer edge of disk'), findsOneWidget);
    await _fill(tester, r);
    await _seeResult(tester);

    expect(
      find.text('Good: the app agrees with your readings within about 1 mm.'),
      findsOneWidget,
    );
    expect(find.textContaining('Bias +0.3 mm'), findsOneWidget);
    expect(find.textContaining('100 % of zones within 1 mm'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);

    final save = find.byKey(const ValueKey('calSave'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await _settleReal(tester, () => store.calibrations.isNotEmpty);
    await tester.pumpAndSettle();
    final p = store.calibrations.single;
    expect(p.cameraName, '0');
    expect(p.setup, CalibrationSetup.stand);
    expect(p.tool, CalibrationTool.calliper);
    expect(p.rimRadiusPx, closeTo(r.plate.radius, 1e-9));
    expect(p.summary.n, 6);
    expect(p.summary.bias, closeTo(0.3, 0.06));
    expect(p.summary.verdict, CalibrationVerdict.good);
    final saved = store.zoneRecords.single;
    expect(saved.usedForCalibration, isTrue);
    expect(saved.calibrationId, p.id);
    expect(saved.marks.every((m) => m.calliperMm.length == 1), isTrue);
    // The app's diameters are untouched.
    expect(
      [for (final m in saved.marks) m.diameterMm],
      [for (final m in r.marks) m.diameterMm],
    );
    expect(find.text('go'), findsOneWidget);
  });

  testWidgets('a scale error shows in the span check and the advice', (
    tester,
  ) async {
    _phone(tester);
    final (store, r) = await _withPlate(tester);
    await _openWizard(tester, store);
    await _useRecent(tester);
    // The user's span 4 % shorter than the app's, zones in step with it.
    await _fill(tester, r, offset: 0.6, spanScale: 1 / 1.04);
    await _seeResult(tester);
    expect(find.textContaining('Usable'), findsOneWidget);
    expect(find.textContaining('differs from yours by +4.0 %'), findsOneWidget);
    expect(find.textContaining('The size scale looks off'), findsOneWidget);
  });

  testWidgets('checks: span, ranges, too few zones, a far reading', (
    tester,
  ) async {
    _phone(tester);
    final (store, r) = await _withPlate(tester);
    await _openWizard(tester, store);
    // A ruler needs 8 zones; this plate has 6.
    await tester.ensureVisible(find.text('Ruler'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ruler'));
    await tester.pumpAndSettle();
    expect(find.text('At least 8 zones are needed.'), findsOneWidget);
    await _useRecent(tester);

    await _seeResult(tester);
    expect(find.text('Enter the span, 20 to 90 mm.'), findsOneWidget);
    await _fill(tester, r);
    await _type(tester, const ValueKey('calZone2'), '120');
    await _seeResult(tester);
    expect(find.text('Zone 3: enter 2 to 90 mm.'), findsOneWidget);
    await _type(tester, const ValueKey('calZone2'), '17');
    await _seeResult(tester);
    expect(find.text('Measure at least 8 zones (6 so far).'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // With a calliper, 6 are enough; a reading 5 mm off asks first.
    await tester.ensureVisible(find.text('Calliper'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Calliper'));
    await tester.pumpAndSettle();
    await _useRecent(tester);
    await _fill(tester, r);
    await _type(
      tester,
      const ValueKey('calZone1'),
      (r.marks[1].reportedMm(6) + 5).toStringAsFixed(1),
    );
    await _seeResult(tester);
    expect(find.text('Check these zones'), findsOneWidget);
    expect(find.textContaining('Zones 2 differ'), findsOneWidget);
    await tester.tap(find.text('They are right'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('calVerdict')), findsOneWidget);
  });

  testWidgets('leaving a zone out; a second reading is averaged', (
    tester,
  ) async {
    _phone(tester);
    final (store, r) = await _withPlate(tester);
    await _openWizard(tester, store);
    await _useRecent(tester);
    await _fill(tester, r);
    final add = find.byTooltip('Not round: add a second reading').first;
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pump();
    await _type(
      tester,
      const ValueKey('calZoneB0'),
      (r.marks[0].reportedMm(6) - 0.5).toStringAsFixed(1),
    );
    // Six zones on this plate: leaving one out is one too few.
    final box = find.byKey(const ValueKey('calInclude5'));
    await tester.ensureVisible(box);
    await tester.tap(box);
    await tester.pump();
    await _seeResult(tester);
    expect(find.text('Measure at least 6 zones (5 so far).'), findsOneWidget);
    await tester.tap(box);
    await tester.pump();
    await _seeResult(tester);
    final save = find.byKey(const ValueKey('calSave'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await _settleReal(tester, () => store.calibrations.isNotEmpty);
    final p = store.calibrations.single;
    expect(p.summary.n, 6);
    final z0 = p.plates.single.zones.first;
    expect(z0.userMm, hasLength(2));
    // (0.3 + 0.5) / 2 below the app.
    expect(
      z0.appMm.single - (z0.userMm[0] + z0.userMm[1]) / 2,
      closeTo(0.4, 0.06),
    );
  });

  testWidgets('add another plate pools them; try again drops the last', (
    tester,
  ) async {
    _phone(tester);
    final (store, r) = await _withPlate(tester);
    await tester.runAsync(() async {
      await store.upsertZone(
        ZoneRecord.fromJson({
          ...r.toJson(),
          'id': 'p2',
          'experiment': 'Second',
        }),
      );
    });
    await _openWizard(tester, store);
    await _useRecent(tester);
    await _fill(tester, r);
    await _seeResult(tester);
    final add = find.text('Add another plate');
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(find.text('Add a plate to this calibration'), findsOneWidget);
    await _useRecent(tester, 'Second');
    await _fill(tester, r, offset: 0.5);
    await _seeResult(tester);
    expect(find.textContaining('· 12 zones'), findsOneWidget);
    final again = find.text('Try again without this plate');
    await tester.ensureVisible(again);
    await tester.tap(again);
    await tester.pumpAndSettle();
    final back = find.text('Back to the result');
    await tester.ensureVisible(back);
    await tester.pumpAndSettle();
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(find.textContaining('· 6 zones'), findsOneWidget);
  });

  testWidgets('the list of calibrations: add a plate, delete', (tester) async {
    _phone(tester);
    final (store, r) = await _withPlate(tester);
    final rr = ZoneRecord.fromJson({
      ...r.toJson(),
      'marks': [
        for (final m in r.marks)
          m.copyWith(calliperMm: [m.reportedMm(6) - 0.2]).toJson(),
      ],
    });
    await tester.runAsync(
      () => store.upsertCalibration(
        CalibrationProfile(
          id: 'c1',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          cameraName: '0',
          imageWidth: r.imageWidth,
          imageHeight: r.imageHeight,
          platform: 'android',
          setup: CalibrationSetup.stand,
          rimRadiusPx: r.plate.radius,
          tool: CalibrationTool.calliper,
          plates: [CalibrationPlate.fromRecord(rr, userSpanMm: 60)],
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: ZoneCalibrationScreen(store: store)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('On the stand ·'), findsOneWidget);
    expect(find.textContaining('1 plate · Calliper'), findsOneWidget);
    await tester.tap(find.text('Add another plate'));
    await tester.pumpAndSettle();
    expect(find.text('Add a plate to this calibration'), findsOneWidget);
    // No tool or setup choice when adding: they come from the profile.
    expect(find.text('Ruler'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(store.calibrations, isEmpty);
    expect(store.zoneRecords, hasLength(1));
  });

  testWidgets('a new plate under a matching calibration is saved with it', (
    tester,
  ) async {
    _phone(tester);
    final (store, r) = await _withPlate(tester);
    await tester.runAsync(
      () => store.upsertCalibration(
        CalibrationProfile(
          id: 'c1',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          cameraName: '0',
          imageWidth: r.imageWidth,
          imageHeight: r.imageHeight,
          platform: 'android',
          setup: CalibrationSetup.stand,
          rimRadiusPx: r.plate.radius,
          tool: CalibrationTool.calliper,
          plates: const [],
        ),
      ),
    );
    Future<ZoneRecord> measure(String camera) async {
      await tester.pumpWidget(const MaterialApp(home: Text('home')));
      final before = store.zoneRecords.length;
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .push(
            MaterialPageRoute<ZoneRecord>(
              builder: (_) => ZoneReviewScreen(
                store: store,
                photo: _photo,
                setup: const ZoneSetup(),
                camera: camera,
              ),
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await _settleReal(
        tester,
        () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save plate'));
      await _settleReal(tester, () => store.zoneRecords.length > before);
      await tester.pumpAndSettle();
      return store.zoneRecords.first;
    }

    final same = await measure('0');
    expect(same.camera, '0');
    expect(same.calibrationId, 'c1');
    final other = await measure('1');
    expect(other.calibrationId, '');
    expect(
      recordCalibration(other, store.calibrations).$1,
      CalibrationStatus.otherCamera,
    );
  });

  testWidgets('first zone plate: the suggestion opens the wizard', (
    tester,
  ) async {
    _phone(tester);
    final store = PlateStore(MemoryStorage());
    await tester.runAsync(store.load);
    await tester.pumpWidget(MaterialApp(home: HomeScreen(store: store)));
    await tester.tap(find.text('Zones').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Measure zones'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('I understand'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Calibrate now'));
    await tester.pumpAndSettle();
    expect(find.text('Check the app against your calliper'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    // From the Zones menu too.
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Calibrate against a calliper'));
    await tester.pumpAndSettle();
    expect(find.byType(ZoneCalibrationScreen), findsOneWidget);
    expect(find.text('New calibration'), findsOneWidget);
  });

  testWidgets('Thai on a small phone: the wizard fits', (tester) async {
    _phone(tester, small: true);
    final (store, r) = await _withPlate(tester);
    await tester.runAsync(() => store.setDefaults(language: 'th'));
    await tester.pumpWidget(ColonyCounterApp(store: store));
    await tester.pumpAndSettle();
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => ZoneCalibrationWizard(store: store),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ตรวจแอปเทียบกับเวอร์เนียร์ของคุณ'), findsOneWidget);
    final b = find.text('ใช้เพลตที่เพิ่งวัด');
    await tester.ensureVisible(b);
    await tester.pumpAndSettle();
    await tester.tap(b);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Extracts ·'));
    await _settleReal(
      tester,
      () => find.text('ตรวจมาตราส่วน').evaluate().isNotEmpty,
    );
    await tester.pumpAndSettle();
    await _fill(tester, r);
    await _seeResult(tester);
    expect(find.byKey(const ValueKey('calVerdict')), findsOneWidget);
    expect(find.text('แอป − ของคุณ'), findsOneWidget);
  });
}
