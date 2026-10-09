import 'dart:io';
import 'dart:typed_data';

import 'package:colony_counter/core/plate.dart';
import 'package:colony_counter/core/zone_calibration.dart';
import 'package:colony_counter/core/zones.dart';
import 'package:colony_counter/data/export.dart';
import 'package:colony_counter/data/plate_store.dart';
import 'package:colony_counter/data/storage/storage.dart';
import 'package:colony_counter/data/zone_calibration_record.dart';
import 'package:colony_counter/data/zone_record.dart';
import 'package:flutter_test/flutter_test.dart';

const _cam = '0';

ZoneMark _mark(double x, double y, double mm, {List<double> cal = const []}) =>
    ZoneMark(
      x: x,
      y: y,
      diskRadiusPx: 30,
      radiusPx: mm / 2 / 0.1,
      diameterMm: mm,
      autoDiameterMm: mm,
      confidence: 0.9,
      calliperMm: cal,
    );

/// Six zones round the plate, the user reading each 0.3 mm smaller.
ZoneRecord _calPlate(String id, {DateTime? at, double rim = 450}) => ZoneRecord(
  id: id,
  createdAt: at ?? DateTime(2026, 10, 9),
  imagePath: '$id.jpg',
  imageWidth: 1000,
  imageHeight: 1000,
  plate: Plate(500, 500, rim),
  mmPerPx: 0.1,
  camera: _cam,
  usedForCalibration: true,
  marks: [
    for (final (x, y, mm) in [
      (500.0, 150.0, 12.0),
      (800.0, 350.0, 16.0),
      (800.0, 650.0, 20.0),
      (500.0, 850.0, 24.0),
      (200.0, 650.0, 28.0),
      (200.0, 350.0, 32.0),
    ])
      _mark(x, y, mm, cal: [mm - 0.3]),
  ],
);

CalibrationProfile _profile(
  List<ZoneRecord> plates, {
  String id = 'c1',
  DateTime? at,
  CalibrationSetup setup = CalibrationSetup.stand,
  double? span,
}) {
  final when = at ?? DateTime(2026, 10, 9);
  return CalibrationProfile(
    id: id,
    createdAt: when,
    updatedAt: when,
    cameraName: _cam,
    imageWidth: 1000,
    imageHeight: 1000,
    platform: 'android',
    setup: setup,
    rimRadiusPx: 450,
    tool: CalibrationTool.calliper,
    plates: [
      for (final r in plates)
        CalibrationPlate.fromRecord(
          r,
          userSpanMm: span ?? recordSpanMm(r, spanPair(r)!),
          addedAt: when,
        ),
    ],
  );
}

void main() {
  group('Calliper readings on zone marks', () {
    test('kept apart from the app diameter, through JSON', () {
      final m = _mark(0, 0, 18.4, cal: [18.0, 18.6]);
      final back = ZoneMark.fromJson(m.toJson());
      expect(back.calliperMm, [18.0, 18.6]);
      expect(back.diameterMm, 18.4);
      expect(back.edited, isFalse);
      expect(back.copyWith(calliperMm: const []).calliperMm, isEmpty);
      expect(ZoneMark.fromJson(_mark(0, 0, 10).toJson()).calliperMm, isEmpty);
    });

    test('zone plates keep the camera and calibration through JSON', () {
      final r = _calPlate('a').copyWith(calibrationId: 'c1');
      final back = ZoneRecord.fromJson(r.toJson());
      expect(back.camera, _cam);
      expect(back.calibrationId, 'c1');
      expect(back.usedForCalibration, isTrue);
      final old = ZoneRecord.fromJson({
        ...r.toJson()
          ..remove('camera')
          ..remove('calibration')
          ..remove('used_for_calibration'),
      });
      expect(old.camera, '');
      expect(old.calibrationId, '');
      expect(old.usedForCalibration, isFalse);
    });
  });

  group('Calibration plates and profiles', () {
    test(
      'a plate snapshot: zones with readings, span across the farthest disks',
      () {
        final r = _calPlate('a');
        final marks = [...r.marks];
        marks[2] = marks[2].copyWith(calliperMm: const []); // not measured
        final rec = r.copyWith(marks: marks);
        final p = CalibrationPlate.fromRecord(
          rec,
          userSpanMm: 76.5,
          excluded: {4},
        );
        expect([for (final z in p.zones) z.mark], [0, 1, 3, 4, 5]);
        expect(p.zones.firstWhere((z) => z.mark == 4).included, isFalse);
        expect(p.zones.first.appMm, [12.0]);
        expect(p.zones.first.userMm, [11.7]);
        expect(p.zones.first.radialFraction, closeTo(350 / 450, 1e-12));
        // 12 and 6 o'clock are farthest apart: 700 px + 2 × 30 px at 0.1 mm/px.
        expect(p.spanMarks, (0, 3));
        expect(p.appSpanMm, closeTo(76, 1e-9));
        final back = CalibrationPlate.fromJson(p.toJson());
        expect(back.spanMarks, (0, 3));
        expect(back.userSpanMm, 76.5);
        expect(
          back.zones.map((z) => z.included),
          p.zones.map((z) => z.included),
        );
      },
    );

    test('no-zone marks report the disk size; doubtful zones are spotted', () {
      final m = _mark(0, 0, 6.2).copyWith(noZone: true);
      final r = _calPlate('a').copyWith(
        marks: [
          m.copyWith(calliperMm: [6.0]),
        ],
      );
      expect(CalibrationPlate.fromRecord(r).zones.single.appMm, [6.0]);
      expect(doubtfulForCalibration(m), isTrue); // no zone: disk size only
      expect(doubtfulForCalibration(_mark(0, 0, 14)), isFalse);
      final hazy = ZoneMark.fromJson({
        ..._mark(0, 0, 14).toJson(),
        'flags': ['hazy'],
      });
      expect(doubtfulForCalibration(hazy), isTrue);
    });

    test('the pooled summary over plates', () {
      final p = _profile([_calPlate('a'), _calPlate('b')]);
      final s = p.summary;
      expect(s.n, 12);
      expect(s.bias, closeTo(0.3, 1e-9));
      expect(s.scaleError, closeTo(0, 1e-12));
      expect(s.verdict, CalibrationVerdict.good);
      // A user span 2 % shorter than the app's shows as a scale error.
      final r = _calPlate('c');
      final off = _profile([r], span: recordSpanMm(r, spanPair(r)!) / 1.02);
      expect(off.summary.scaleError, closeTo(0.02, 1e-9));
      expect(off.summary.verdict, CalibrationVerdict.usable);
      expect(off.summary.hint, CalibrationHint.scale);
    });

    test('adding a plate again replaces its snapshot', () {
      final p = _profile([_calPlate('a')]);
      final again = p.withPlate(
        CalibrationPlate.fromRecord(
          _calPlate('a'),
          addedAt: DateTime(2026, 11, 1),
        ),
      );
      expect(again.plates, hasLength(1));
      expect(again.updatedAt, DateTime(2026, 11, 1));
      expect(
        again.withPlate(CalibrationPlate.fromRecord(_calPlate('b'))).plates,
        hasLength(2),
      );
    });

    test('JSON round trip', () {
      final p = _profile([_calPlate('a')]).copyWith(name: 'Stand, main camera');
      final back = CalibrationProfile.fromJson(p.toJson());
      expect(back.toJson(), p.toJson());
      expect(back.summary.bias, closeTo(p.summary.bias, 1e-12));
      expect(back.setup, CalibrationSetup.stand);
    });
  });

  group('Matching a plate to its calibration', () {
    final profile = _profile([_calPlate('a')]);
    ZoneRecord plate({
      String camera = _cam,
      int w = 1000,
      int h = 1000,
      double rim = 450,
      DateTime? at,
      String calibrationId = '',
    }) => _calPlate('p', rim: rim, at: at ?? DateTime(2026, 10, 20))
        .copyWith(camera: camera, calibrationId: calibrationId)
        .let(
          (r) => ZoneRecord.fromJson({
            ...r.toJson(),
            'image_width': w,
            'image_height': h,
          }),
        );

    CalibrationStatus status(ZoneRecord r, [List<CalibrationProfile>? ps]) =>
        recordCalibration(r, ps ?? [profile]).$1;

    test('same camera, size and stand height within 90 days: calibrated', () {
      expect(status(plate()), CalibrationStatus.calibrated);
      expect(status(plate(rim: 460)), CalibrationStatus.calibrated); // 2 %
      expect(status(plate(w: 1000, h: 1000)), CalibrationStatus.calibrated);
      expect(recordCalibration(plate(), [profile]).$2?.id, 'c1');
    });

    test('a different stand height, lens or photo size', () {
      expect(status(plate(rim: 470)), CalibrationStatus.setupChanged); // 4.4 %
      expect(status(plate(camera: '2')), CalibrationStatus.otherCamera);
      expect(status(plate(w: 1200)), CalibrationStatus.otherCamera);
    });

    test('hand-held profiles have no height to compare', () {
      final hand = _profile([_calPlate('a')], setup: CalibrationSetup.handheld);
      expect(status(plate(rim: 300), [hand]), CalibrationStatus.calibrated);
    });

    test('older than 90 days on the day of the photo', () {
      expect(
        status(plate(at: DateTime(2027, 1, 6))),
        CalibrationStatus.calibrated,
      );
      expect(status(plate(at: DateTime(2027, 1, 8))), CalibrationStatus.old);
      expect(calibrationFlags(CalibrationStatus.old), ['calibration_old']);
    });

    test('never calibrated, or calibrated for another lens only', () {
      expect(status(plate(), const []), CalibrationStatus.uncalibrated);
      expect(calibrationFlags(CalibrationStatus.uncalibrated), [
        'uncalibrated',
      ]);
      expect(status(plate(camera: '1')), CalibrationStatus.otherCamera);
      expect(calibrationFlags(CalibrationStatus.calibrated), isEmpty);
    });

    test('the newest profile for the camera is the active one', () {
      final newer = _profile(
        [_calPlate('b')],
        id: 'c2',
        at: DateTime(2026, 10, 15),
      );
      final other = CalibrationProfile.fromJson({
        ...newer.toJson(),
        'id': 'c3',
        'camera': '1',
        'updated_at': DateTime(2026, 10, 19).toIso8601String(),
      });
      expect(
        activeCalibration(
          [profile, newer, other],
          camera: _cam,
          width: 1000,
          height: 1000,
        )?.id,
        'c2',
      );
      // A plate saved with a profile keeps it, even when a newer one exists.
      expect(
        recordCalibration(plate(calibrationId: 'c1'), [profile, newer]).$2?.id,
        'c1',
      );
    });

    test('statusAgainst for the camera right now (no plate yet)', () {
      expect(
        statusAgainst(
          profile,
          camera: _cam,
          width: 1000,
          height: 1000,
          at: DateTime(2027, 2, 1),
        ),
        CalibrationStatus.old,
      );
      expect(
        statusAgainst(
          null,
          camera: _cam,
          width: 1000,
          height: 1000,
          at: DateTime(2026, 10, 10),
        ),
        CalibrationStatus.uncalibrated,
      );
    });
  });

  group('Store and backup', () {
    test('profiles are stored, reloaded newest first and deleted', () async {
      final backend = MemoryStorage();
      final store = PlateStore(backend);
      await store.load();
      await store.upsertCalibration(_profile([_calPlate('a')]));
      await store.upsertCalibration(
        _profile([_calPlate('b')], id: 'c2', at: DateTime(2026, 10, 12)),
      );
      final again = PlateStore(backend);
      await again.load();
      expect(again.calibrations.map((p) => p.id), ['c2', 'c1']);
      expect(again.calibrations.last.summary.n, 6);
      await again.deleteCalibration(again.calibrations.first);
      expect(again.calibrations.single.id, 'c1');
    });

    test('backup and restore carry profiles and calibration plates', () async {
      final store = PlateStore(MemoryStorage());
      await store.load();
      final r = _calPlate('a');
      await store.savePhoto(Uint8List.fromList([1, 2, 3]), 'a');
      await store.upsertZone(r.copyWith(calibrationId: 'c1'));
      await store.upsertCalibration(_profile([r]));
      final zip = await buildBackup(store);

      final fresh = PlateStore(MemoryStorage());
      await fresh.load();
      await restoreBackup(fresh, zip);
      expect(fresh.calibrations.single.id, 'c1');
      expect(fresh.calibrations.single.summary.bias, closeTo(0.3, 1e-9));
      final z = fresh.zoneRecords.single;
      expect(z.usedForCalibration, isTrue);
      expect(z.marks.first.calliperMm, [11.7]);

      // Again: nothing doubles.
      await restoreBackup(fresh, zip);
      expect(fresh.calibrations, hasLength(1));
    });

    test('a store from before calibration loads with none', () async {
      final backend = MemoryStorage();
      final store = PlateStore(backend);
      await store.load();
      await store.upsertZone(_calPlate('a'));
      final again = PlateStore(backend);
      await again.load();
      expect(again.calibrations, isEmpty);
    });
  });

  test('a measured photo gives the scale span used for calibration', () {
    final res = measureZonesInPhoto((
      File('test/fixtures/zones_reflected.jpg').readAsBytesSync(),
      const ZoneOptions(),
    ));
    final r = ZoneRecord.fromResult(
      res,
      id: 'z',
      imagePath: 'z.jpg',
      createdAt: DateTime(2026, 10, 9),
      camera: _cam,
    );
    expect(r.camera, _cam);
    final pair = spanPair(r)!;
    // Two of six disks, measured at the disk-based scale: 40–80 mm on a 90 mm dish.
    expect(recordSpanMm(r, pair), inInclusiveRange(40, 80));
  });
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
