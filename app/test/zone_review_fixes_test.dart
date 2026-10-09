import 'dart:io';

import 'package:colony_counter/core/plate.dart';
import 'package:colony_counter/core/zone_calibration.dart';
import 'package:colony_counter/core/zones.dart';
import 'package:colony_counter/data/calibration_export.dart';
import 'package:colony_counter/data/export.dart';
import 'package:colony_counter/data/plate_store.dart';
import 'package:colony_counter/data/storage/storage.dart';
import 'package:colony_counter/data/zone_calibration_record.dart';
import 'package:colony_counter/data/zone_record.dart';
import 'package:colony_counter/ui/zone_calibration_screen.dart';
import 'package:colony_counter/ui/zone_review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Regression tests for the October 2026 code review of the zone and
// calibration features.

final _photo = File('test/fixtures/zones_reflected.jpg').readAsBytesSync();
final _measured = measureZonesInPhoto((_photo, const ZoneOptions()));

ZoneRecord _plate({String id = 'p1', DateTime? at, String camera = '0'}) =>
    ZoneRecord.fromResult(
      _measured,
      id: id,
      imagePath: 'zone_$id.jpg',
      createdAt: at ?? DateTime(2026, 10, 9),
      experiment: 'Extracts',
      camera: camera,
    );

ZoneRecord _read(ZoneRecord r, {double offset = 0.2}) => r.copyWith(
  marks: [
    for (final m in r.marks) m.copyWith(calliperMm: [m.reportedMm(6) - offset]),
  ],
);

CalibrationProfile _profile(
  List<ZoneRecord> plates, {
  String id = 'c1',
  DateTime? at,
  double? rim,
}) {
  final when = at ?? DateTime(2026, 10, 9);
  final r = plates.first;
  return CalibrationProfile(
    id: id,
    createdAt: when,
    updatedAt: when,
    cameraName: '0',
    imageWidth: r.imageWidth,
    imageHeight: r.imageHeight,
    platform: 'android',
    setup: CalibrationSetup.stand,
    rimRadiusPx: rim ?? r.plate.radius,
    tool: CalibrationTool.calliper,
    plates: [
      for (final p in plates)
        CalibrationPlate.fromRecord(
          p,
          userSpanMm: recordSpanMm(p, spanPair(p)!),
          addedAt: when,
        ),
    ],
  );
}

void main() {
  group('Calibration snapshots survive later edits', () {
    test('the export uses the positions as calibrated, not the mark index', () {
      final r = _read(_plate());
      final profile = _profile([r]);
      final before = calibrationLabel(r, profile.plates.single, profile);
      // Delete mark 1: every later index shifts.
      final edited = r.copyWith(marks: [...r.marks]..removeAt(1));
      final after = calibrationLabel(edited, profile.plates.single, profile);
      final b = (before['zones'] as List).cast<Map<String, dynamic>>();
      final a = (after['zones'] as List).cast<Map<String, dynamic>>();
      expect(a.length, b.length);
      for (var i = 0; i < a.length; i++) {
        expect(a[i]['x'], b[i]['x']);
        expect(a[i]['diameter_mm'], b[i]['diameter_mm']);
      }
      expect(after['span_disks'], before['span_disks']);
    });

    test('an old snapshot with stale span marks no longer crashes', () {
      final r = _read(_plate());
      final p = _profile([r]);
      final json = p.plates.single.toJson()
        ..remove('span_disks')
        ..['span_marks'] = [0, 40];
      final stale = CalibrationPlate.fromJson(json);
      final label = calibrationLabel(r, stale, p);
      expect(label.containsKey('span_disks'), isFalse);
      expect(label.containsKey('span_mm'), isFalse);
    });

    test('no span reading is stored as none, not 0', () {
      final r = _read(_plate());
      final plate = CalibrationPlate.fromRecord(r, userSpanMm: 0);
      expect(plate.userSpanMm, isNull);
      expect(plate.hasSpan, isFalse);
    });

    test(
      'readings follow their disks when marks are re-ordered or measured again',
      () {
        final r = _read(_plate());
        final shuffled = [
          ...r.marks.reversed,
        ].map((m) => m.copyWith(calliperMm: const [])).toList()..removeAt(2);
        final carried = carryUserData(r.marks, shuffled);
        for (final m in carried) {
          final o = r.marks.firstWhere((x) => x.x == m.x && x.y == m.y);
          expect(m.calliperMm, o.calliperMm);
        }
      },
    );
  });

  group('Matching and the gate', () {
    test('a profile from the same stand height is preferred', () {
      final r = _plate();
      final near = _profile([_read(r)], id: 'near', at: DateTime(2026, 10, 1));
      final far = _profile(
        [_read(r)],
        id: 'far',
        at: DateTime(2026, 10, 8),
        rim: r.plate.radius * 1.5,
      );
      final (status, p) = recordCalibration(r, [near, far]);
      expect(p?.id, 'near');
      expect(status, CalibrationStatus.calibrated);
    });

    test('a photo long before the calibration is not covered by it', () {
      final p = _profile([_read(_plate())], at: DateTime(2026, 10, 9));
      final early = _plate(at: DateTime(2025, 1, 1));
      expect(recordCalibration(early, [p]).$1, CalibrationStatus.old);
    });

    test('a plate in two profiles counts once in the gate', () {
      final r = _read(_plate());
      final a = _profile([r], id: 'a');
      final b = _profile(
        [_read(r, offset: 1.0)],
        id: 'b',
        at: DateTime(2026, 10, 10),
      );
      final g = gateProgress([a, b]);
      expect(g.plates, 1);
      expect(g.zones, a.plates.single.zones.length);
      expect(g.meanAbsError, closeTo(1.0, 1e-9)); // the newer snapshot
    });
  });

  group('Store and CSV', () {
    test(
      'deleting a profile turns its plates back into ordinary plates',
      () async {
        final store = PlateStore(MemoryStorage());
        await store.load();
        final r = _read(_plate())
            .copyWith(usedForCalibration: true, calibrationId: 'c1');
        await store.upsertZone(r);
        await store.upsertCalibration(_profile([r]));
        await store.deleteCalibration(store.calibrations.single);
        final z = store.zoneRecords.single;
        expect(z.usedForCalibration, isFalse);
        expect(z.calibrationId, '');
        expect(z.marks.first.calliperMm, isNotEmpty); // readings kept
      },
    );

    test('zones.csv has the plate flags', () async {
      final store = PlateStore(MemoryStorage());
      await store.load();
      await store.upsertZone(
        _plate().copyWith(flags: const ['scale_mismatch']),
      );
      final lines = zonesCsv(store).trim().split('\n');
      final head = lines.first.split(',');
      final row = Map.fromIterables(head, lines[1].split(','));
      expect(row['plate_flags'], 'scale_mismatch');
    });
  });

  group('Scale and positions from the detector', () {
    test('no-zone disks are left out of the zone scale', () {
      final r = _plate();
      for (final m in r.marks.where(
        (m) => m.diameterMm.isFinite && !m.noZone,
      )) {
        expect(m.diameterMm, closeTo(2 * m.radiusPx * r.mmPerPx, 1e-6));
      }
      // Wells: the rim scale is used as it is, not "corrected" by the disks.
      const wells = ZoneResult(
        plate: Plate(500, 500, 450),
        assay: ZoneAssay.well,
        zones: [],
        polarity: 'dark_zone',
        diskScaleRatio: 1.04,
        flags: [],
        imageWidth: 1000,
        imageHeight: 1000,
      );
      expect(zoneScale(wells), const Plate(500, 500, 450).mmPerPx);
    });

    test('marks sit on the disk, not the fitted zone centre', () {
      for (final z in _measured.zones) {
        final m = ZoneMark.fromZone(z);
        expect(m.x, z.diskX);
        expect(m.y, z.diskY);
      }
      final z = _measured.zones.first;
      final back = Zone.fromJson(z.toJson());
      expect(back.diskX, closeTo(z.diskX, 1e-9));
    });
  });

  group('Review screen and wizard', () {
    Future<void> settle(WidgetTester t, bool Function() done) async {
      for (var i = 0; i < 300 && !done(); i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await t.pump();
      }
    }

    testWidgets('saving an open plate keeps a calibration made meanwhile', (
      t,
    ) async {
      t.view.physicalSize = const Size(1080, 2340);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final store = PlateStore(MemoryStorage());
      final r = _plate(at: DateTime.now());
      await t.runAsync(() async {
        await store.load();
        await store.savePhoto(_photo, 'zone_p1');
        await store.upsertZone(r);
      });
      await t.pumpWidget(
        MaterialApp(
          home: ZoneReviewScreen(store: store, record: r),
        ),
      );
      await settle(
        t,
        () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
      );
      await t.pumpAndSettle();
      // Meanwhile the plate is calibrated (as from its chip).
      await t.runAsync(
        () => store.upsertZone(
          _read(r).copyWith(usedForCalibration: true, calibrationId: 'c1'),
        ),
      );
      // An edit, then save: the calibration and readings must survive.
      final chip = find.byKey(const ValueKey('zoneChip1'));
      await t.ensureVisible(chip);
      await t.tap(chip);
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('1 mm larger'));
      await t.tap(find.text('Done'));
      await t.pumpAndSettle();
      await t.tap(find.text('Save changes'));
      await settle(
        t,
        () =>
            store.zoneRecords.single.marks[1].diameterMm !=
            r.marks[1].diameterMm,
      );
      final saved = store.zoneRecords.single;
      expect(saved.usedForCalibration, isTrue);
      expect(saved.calibrationId, 'c1');
      expect(saved.marks.every((m) => m.calliperMm.isNotEmpty), isTrue);
    });

    testWidgets('a calibration plate is not offered again', (t) async {
      t.view.physicalSize = const Size(1080, 2340);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final store = PlateStore(MemoryStorage());
      await t.runAsync(() async {
        await store.load();
        await store.upsertZone(
          _plate(
            id: 'used',
            at: DateTime.now(),
          ).copyWith(usedForCalibration: true, calibrationId: 'c1'),
        );
      });
      await t.pumpWidget(
        MaterialApp(home: ZoneCalibrationWizard(store: store)),
      );
      await t.pumpAndSettle();
      final b = find.text('Use a plate I just measured');
      await t.ensureVisible(b);
      await t.tap(b);
      await t.pumpAndSettle();
      expect(find.text('No zone plates from the last day.'), findsOneWidget);
    });

    testWidgets('a plate photographed for calibration is only flagged by the '
        'wizard', (t) async {
      t.view.physicalSize = const Size(1080, 2340);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final store = PlateStore(MemoryStorage());
      await t.runAsync(store.load);
      await t.pumpWidget(const MaterialApp(home: Text('home')));
      t
          .state<NavigatorState>(find.byType(Navigator))
          .push(
            MaterialPageRoute<ZoneRecord>(
              builder: (_) => ZoneReviewScreen(
                store: store,
                photo: _photo,
                setup: const ZoneSetup(),
                camera: '0',
                forCalibration: true,
              ),
            ),
          );
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      await settle(
        t,
        () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Save plate'));
      await settle(t, () => store.zoneRecords.isNotEmpty);
      // Leaving the wizard now leaves an ordinary plate, not an orphan
      // "calibration plate".
      expect(store.zoneRecords.single.usedForCalibration, isFalse);
      expect(store.zoneRecords.single.calibrationId, '');
    });
  });
}
