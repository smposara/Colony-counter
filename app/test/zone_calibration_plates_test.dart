import 'dart:convert';
import 'dart:io';

import 'package:colony_counter/core/zone_calibration.dart';
import 'package:colony_counter/core/zones.dart';
import 'package:colony_counter/data/export.dart';
import 'package:colony_counter/data/plate_store.dart';
import 'package:colony_counter/data/storage/storage.dart';
import 'package:colony_counter/data/zone_calibration_record.dart';
import 'package:colony_counter/data/zone_record.dart';
import 'package:colony_counter/ui/home_screen.dart';
import 'package:colony_counter/ui/zone_calibration_screen.dart';
import 'package:colony_counter/ui/zone_review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _photo = File('test/fixtures/zones_reflected.jpg').readAsBytesSync();
final _measured = measureZonesInPhoto((_photo, const ZoneOptions()));

ZoneRecord _plate({
  String id = 'p1',
  String camera = '0',
  DateTime? at,
  ZoneAssay assay = ZoneAssay.disk,
}) {
  final r = ZoneRecord.fromResult(
    _measured,
    id: id,
    imagePath: '$id.jpg',
    createdAt: at ?? DateTime.now(),
    experiment: 'Extracts',
    camera: camera,
  );
  return assay == ZoneAssay.disk
      ? r
      : ZoneRecord.fromJson({...r.toJson(), 'assay': assay.name});
}

/// A profile from the fixture plate, readings 0.2 mm below the app's; the
/// user's span is [spanScale] × the app's.
CalibrationProfile _profile({
  DateTime? at,
  String camera = '0',
  double spanScale = 1,
  CalibrationSetup setup = CalibrationSetup.stand,
}) {
  final r = _plate(id: 'cal', camera: camera);
  final read = r.copyWith(
    marks: [
      for (final m in r.marks) m.copyWith(calliperMm: [m.reportedMm(6) - 0.2]),
    ],
  );
  final when = at ?? DateTime.now();
  return CalibrationProfile(
    id: 'c1',
    createdAt: when,
    updatedAt: when,
    cameraName: camera,
    imageWidth: r.imageWidth,
    imageHeight: r.imageHeight,
    platform: 'android',
    setup: setup,
    rimRadiusPx: r.plate.radius,
    tool: CalibrationTool.calliper,
    plates: [
      CalibrationPlate.fromRecord(
        read,
        userSpanMm: recordSpanMm(read, spanPair(read)!) * spanScale,
        excluded: const {},
        addedAt: when,
      ),
    ],
  );
}

Future<PlateStore> _store(
  WidgetTester tester, {
  List<CalibrationProfile> profiles = const [],
  bool disclaimerSeen = true,
}) async {
  final store = PlateStore(MemoryStorage());
  await tester.runAsync(() async {
    await store.load();
    for (final p in profiles) {
      await store.upsertCalibration(p);
    }
    if (disclaimerSeen) await store.acceptZoneDisclaimer();
  });
  return store;
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _settleReal(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 300 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
  }
}

/// A saved plate opened on the review screen.
Future<void> _review(
  WidgetTester tester,
  PlateStore store,
  ZoneRecord r,
) async {
  await tester.runAsync(() async {
    await store.savePhoto(_photo, r.id);
    await store.upsertZone(r);
  });
  await tester.pumpWidget(
    MaterialApp(
      key: UniqueKey(),
      home: ZoneReviewScreen(store: store, record: store.zoneRecords.first),
    ),
  );
  await _settleReal(
    tester,
    () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
  );
  await tester.pumpAndSettle();
}

String _chip(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('calChip')),
        matching: find.byType(Text),
      ),
    )
    .data!;

void main() {
  group('The true scale and a plate against it', () {
    test('span in pixels is kept and gives the true scale', () {
      final p = _profile(spanScale: 1.03);
      final plate = p.plates.single;
      expect(plate.spanPx, closeTo(plate.appSpanMm! / _plate().mmPerPx, 1e-9));
      expect(
        CalibrationPlate.fromJson(plate.toJson()).spanPx,
        closeTo(plate.spanPx!, 1e-9),
      );
      expect(p.trueMmPerPx, closeTo(_plate().mmPerPx * 1.03, 1e-12));
    });

    test('a plate whose scale is 3 % small reads 3 % small', () {
      final p = _profile(spanScale: 1.03);
      final d = scaleAgainstCalibration(
        _plate(),
        CalibrationStatus.calibrated,
        p,
      );
      expect(d, closeTo(1 / 1.03 - 1, 1e-9));
      // Only for a calibrated plate on a fixed stand.
      expect(
        scaleAgainstCalibration(_plate(), CalibrationStatus.old, p),
        isNull,
      );
      expect(
        scaleAgainstCalibration(
          _plate(),
          CalibrationStatus.calibrated,
          _profile(setup: CalibrationSetup.handheld),
        ),
        isNull,
      );
    });
  });

  group('Review screen chip and notes', () {
    testWidgets('not calibrated', (tester) async {
      _phone(tester);
      final store = await _store(tester);
      await _review(tester, store, _plate());
      expect(_chip(tester), 'Not calibrated');
      await tester.tap(find.byKey(const ValueKey('calChip')));
      await tester.pumpAndSettle();
      expect(find.byType(ZoneCalibrationScreen), findsOneWidget);
    });

    testWidgets('calibrated: verdict and bias', (tester) async {
      _phone(tester);
      final store = await _store(tester, profiles: [_profile()]);
      await _review(tester, store, _plate());
      expect(_chip(tester), 'Calibrated: good · bias +0.2 mm');
      expect(find.textContaining('Calibrate again'), findsNothing);
      expect(find.textContaining('Zones may read'), findsNothing);
    });

    testWidgets('another camera: calibrate again, with the reason', (
      tester,
    ) async {
      _phone(tester);
      final store = await _store(tester, profiles: [_profile()]);
      await _review(tester, store, _plate(camera: '2'));
      expect(_chip(tester), 'Calibrate again');
      expect(
        find.textContaining('another camera or photo size'),
        findsOneWidget,
      );
    });

    testWidgets('more than 90 days after the calibration', (tester) async {
      _phone(tester);
      final store = await _store(
        tester,
        profiles: [
          _profile(at: DateTime.now().subtract(const Duration(days: 120))),
        ],
      );
      await _review(tester, store, _plate());
      expect(_chip(tester), 'Calibrate again');
      expect(find.textContaining('more than 90 days older'), findsOneWidget);
    });

    testWidgets('a scale off the calibrated one: disks and wells', (
      tester,
    ) async {
      _phone(tester);
      final store = await _store(tester, profiles: [_profile(spanScale: 1.05)]);
      await _review(tester, store, _plate());
      expect(
        find.textContaining('Zones may read about 5 % small'),
        findsOneWidget,
      );
      expect(find.textContaining('Check the disk size'), findsOneWidget);

      final wells = await _store(tester, profiles: [_profile(spanScale: 1.05)]);
      await _review(tester, wells, _plate(assay: ZoneAssay.well));
      expect(
        find.textContaining('Zones may read about 5 % small'),
        findsOneWidget,
      );
      expect(find.textContaining('dish rim'), findsOneWidget);
    });

    testWidgets('a calibration plate says so', (tester) async {
      _phone(tester);
      final store = await _store(tester, profiles: [_profile()]);
      await _review(tester, store, _plate().copyWith(usedForCalibration: true));
      expect(_chip(tester), 'Calibration plate');
    });
  });

  group('Zones tab', () {
    Future<void> tab(WidgetTester tester, PlateStore store) async {
      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          home: HomeScreen(store: store),
        ),
      );
      await tester.tap(find.text('Zones').last);
      await tester.pumpAndSettle();
    }

    testWidgets('banner: not calibrated, then Calibrate opens the wizard', (
      tester,
    ) async {
      _phone(tester);
      final store = await _store(tester);
      await tab(tester, store);
      expect(
        find.text('Not calibrated: check the app against your calliper.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Calibrate'));
      await tester.pumpAndSettle();
      expect(find.text('Check the app against your calliper'), findsOneWidget);
    });

    testWidgets('banner: calibrated, or more than 90 days old', (tester) async {
      _phone(tester);
      await tab(tester, await _store(tester, profiles: [_profile()]));
      expect(find.textContaining('Calibrated: good ·'), findsOneWidget);
      expect(find.text('Calibrate'), findsNothing);

      await tab(
        tester,
        await _store(
          tester,
          profiles: [
            _profile(at: DateTime.now().subtract(const Duration(days: 91))),
          ],
        ),
      );
      expect(
        find.text(
          'Your calibration is more than 90 days old: calibrate again.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('an old calibration is offered again before the next plate', (
      tester,
    ) async {
      _phone(tester);
      final store = await _store(
        tester,
        profiles: [
          _profile(at: DateTime.now().subtract(const Duration(days: 100))),
        ],
      );
      await tab(tester, store);
      await tester.tap(find.text('Measure zones'));
      await tester.pumpAndSettle();
      expect(find.text('Calibrate again?'), findsOneWidget);
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(find.text('Paper disks'), findsOneWidget);

      // A recent calibration: straight to the setup.
      final fresh = await _store(tester, profiles: [_profile()]);
      await tab(tester, fresh);
      await tester.tap(find.text('Measure zones'));
      await tester.pumpAndSettle();
      expect(find.text('Calibrate again?'), findsNothing);
      expect(find.text('Paper disks'), findsOneWidget);
    });
  });

  group('Exports', () {
    test('zones.csv: calliper readings and the calibration', () async {
      final store = PlateStore(MemoryStorage());
      await store.load();
      await store.upsertCalibration(_profile());
      final cal = _plate(id: 'cal').copyWith(
        usedForCalibration: true,
        calibrationId: 'c1',
        marks: [
          for (final m in _plate().marks) m.copyWith(calliperMm: [10.0, 10.5]),
        ],
      );
      await store.upsertZone(cal);
      await store.upsertZone(_plate(id: 'other', camera: '9'));
      final lines = const LineSplitter().convert(zonesCsv(store));
      final head = lines.first.split(',');
      Map<String, String> row(int i) =>
          Map.fromIterables(head, lines[i].split(','));
      for (final c in [
        'calliper_mm',
        'used_for_calibration',
        'calibration_id',
        'calibration_status',
        'calibration_verdict',
        'calibration_bias_mm',
      ]) {
        expect(head, contains(c));
      }
      final calRow = [for (var i = 1; i < lines.length; i++) row(i)]
          .firstWhere((r) => r['plate_id'] == 'cal');
      expect(calRow['calliper_mm'], '10.3');
      expect(calRow['used_for_calibration'], 'true');
      expect(calRow['calibration_id'], 'c1');
      expect(calRow['calibration_status'], 'calibrated');
      expect(calRow['calibration_verdict'], 'good');
      expect(calRow['calibration_bias_mm'], '0.2');
      final other = [for (var i = 1; i < lines.length; i++) row(i)]
          .firstWhere((r) => r['plate_id'] == 'other');
      expect(other['calibration_status'], 'other_camera');
      expect(other['calliper_mm'], '');
    });

    test('the shared photo banner names the calibration', () {
      final p = _profile();
      final r = _plate();
      final (status, profile) = recordCalibration(r, [p]);
      expect(
        calibrationBannerLine(r, status, profile),
        startsWith('Calibrated against a calliper: good, bias 0.2 mm'),
      );
      expect(
        calibrationBannerLine(r, CalibrationStatus.uncalibrated, null),
        'Not calibrated against a calliper',
      );
      expect(zoneAnnotationHeader(r, calibration: 'X').last, 'X');
      expect(zoneAnnotationHeader(r), hasLength(3));
    });
  });
}
