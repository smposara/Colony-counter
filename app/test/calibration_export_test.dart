import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:colony_counter/core/zone_calibration.dart';
import 'package:colony_counter/core/zones.dart';
import 'package:colony_counter/data/calibration_export.dart';
import 'package:colony_counter/data/plate_store.dart';
import 'package:colony_counter/data/storage/storage.dart';
import 'package:colony_counter/data/zone_calibration_record.dart';
import 'package:colony_counter/data/zone_record.dart';
import 'package:colony_counter/ui/zone_calibration_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _photo = File('test/fixtures/zones_reflected.jpg').readAsBytesSync();
final _measured = measureZonesInPhoto((_photo, const ZoneOptions()));

/// A calibration plate from the fixture, read [offset] mm below the app.
ZoneRecord _calPlate(String id, {double offset = 0.2}) {
  final r = ZoneRecord.fromResult(
    _measured,
    id: id,
    imagePath: 'zone_$id.jpg',
    createdAt: DateTime(2026, 10, 9),
    camera: '0',
  );
  return r.copyWith(
    usedForCalibration: true,
    marks: [
      for (final m in r.marks)
        m.copyWith(calliperMm: [m.reportedMm(6) - offset]),
    ],
  );
}

CalibrationProfile _profile(
  List<ZoneRecord> plates, {
  String id = 'c1',
  CalibrationTool tool = CalibrationTool.calliper,
  Set<int> excluded = const {0},
}) => CalibrationProfile(
  id: id,
  createdAt: DateTime(2026, 10, 9),
  updatedAt: DateTime(2026, 10, 9),
  cameraName: '0',
  imageWidth: plates.first.imageWidth,
  imageHeight: plates.first.imageHeight,
  platform: 'android',
  setup: CalibrationSetup.stand,
  rimRadiusPx: plates.first.plate.radius,
  tool: tool,
  plates: [
    for (final r in plates)
      CalibrationPlate.fromRecord(
        r,
        userSpanMm: recordSpanMm(r, spanPair(r)!),
        excluded: excluded,
        addedAt: DateTime(2026, 10, 9),
      ),
  ],
);

void main() {
  group('Gate progress', () {
    test('pooled over calliper plates only', () {
      final g = gateProgress([
        _profile([_calPlate('a'), _calPlate('b', offset: 1.5)]),
        _profile(
          [_calPlate('r', offset: 3)],
          id: 'c2',
          tool: CalibrationTool.ruler,
        ),
      ]);
      expect(g.plates, 2);
      expect(g.zones, 10); // 5 included zones each
      expect(g.meanAbsError, closeTo((0.2 + 1.5) / 2, 1e-9));
      expect(g.within2mm, 1);
      expect(g.enoughPlates, isFalse);
      expect(g.met, isFalse);
    });

    test('met on 30 plates within the limits, not with large errors', () {
      final good = _profile([for (var i = 0; i < 30; i++) _calPlate('g$i')]);
      expect(gateProgress([good]).met, isTrue);
      final poor = _profile([
        for (var i = 0; i < 30; i++)
          _calPlate('p$i', offset: i.isEven ? 0.2 : 2.5),
      ]);
      final g = gateProgress([poor]);
      expect(g.enoughPlates, isTrue);
      expect(g.within2mm, closeTo(0.5, 1e-9));
      expect(g.met, isFalse);
      expect(gateProgress(const []).zones, 0);
    });
  });

  group('Test-data zip', () {
    Future<(PlateStore, Archive)> build() async {
      final store = PlateStore(MemoryStorage());
      await store.load();
      final a = _calPlate('a');
      await store.savePhoto(_photo, 'zone_a');
      await store.upsertZone(a);
      // A plate whose record was deleted is skipped.
      await store.upsertCalibration(_profile([a, _calPlate('gone')]));
      final zip = ZipDecoder().decodeBytes(
        await buildCalibrationTestData(store),
      );
      return (store, zip);
    }

    test('a photo and an evaluate-zones label per plate', () async {
      final (_, zip) = await build();
      final names = [for (final f in zip.files) f.name]..sort();
      expect(names, [
        'README.txt',
        'profiles.json',
        'zone_a.jpg',
        'zone_a.json',
      ]);
      final label = jsonDecode(
        utf8.decode(zip.findFile('zone_a.json')!.content),
      ) as Map<String, dynamic>;
      expect(label['plate_mm'], 90);
      expect(label['assay'], 'disk');
      expect(label['disk_mm'], 6);
      expect(label['tool'], 'calliper');
      expect(label['camera'], '0');
      expect(label['setup'], 'stand');
      expect(label['span_mm'], isA<num>());
      expect(label['span_disks'], hasLength(2));
      final zones = (label['zones'] as List).cast<Map<String, dynamic>>();
      expect(zones, hasLength(5));
      for (final z in zones) {
        expect(
          z.keys,
          containsAll(['x', 'y', 'diameter_mm', 'readings_mm', 'app_mm']),
        );
        expect(
          (z['app_mm'] as num) - (z['diameter_mm'] as num),
          closeTo(0.2, 0.011),
        );
      }
      // The no-zone disk the user left out is listed apart.
      final excluded = (label['excluded'] as List).cast<Map<String, dynamic>>();
      expect(excluded.single['no_zone'], isTrue);
      expect(zip.findFile('zone_a.jpg')!.content, _photo);
    });

    test('profiles.json carries the summaries and the gate', () async {
      final (_, zip) = await build();
      final j = jsonDecode(
        utf8.decode(zip.findFile('profiles.json')!.content),
      ) as Map<String, dynamic>;
      expect(j['format'], 'colony-counter-zone-calibration');
      final gate = j['gate'] as Map<String, dynamic>;
      expect(gate['plates'], 2);
      expect(gate['met'], isFalse);
      final p = (j['profiles'] as List).single as Map<String, dynamic>;
      expect(p['id'], 'c1');
      expect((p['summary'] as Map)['verdict'], 'good');
      expect(
        utf8.decode(zip.findFile('README.txt')!.content),
        contains('colonycounter evaluate-zones'),
      );
    });

    test(
      'readable by the Python evaluate-zones (written out for a check)',
      () async {
        // Writes the zip's files to a folder when COLONY_CAL_OUT is set, so the
        // Python CLI can be run on them by hand: see the C5 note in
        // docs/ZONE_CALIBRATION_IMPLEMENTATION.md.
        final out = Platform.environment['COLONY_CAL_OUT'];
        if (out == null) return;
        final (_, zip) = await build();
        for (final f in zip.files) {
          File('$out/${f.name}')
            ..createSync(recursive: true)
            ..writeAsBytesSync(f.content);
        }
      },
    );
  });

  testWidgets('calibrations screen: gate line and share button', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final store = PlateStore(MemoryStorage());
    await tester.runAsync(() async {
      await store.load();
      await store.upsertCalibration(_profile([_calPlate('a')]));
    });
    await tester.pumpWidget(
      MaterialApp(home: ZoneCalibrationScreen(store: store)),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Test data: 1 of 30 calliper plates · mean error 0.2 mm · 100 % within 2 mm',
      ),
      findsOneWidget,
    );
    final share = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.ios_share),
    );
    expect(share.onPressed, isNotNull);
    await tester.tap(find.byTooltip('Share as test data'));
    await tester.pumpAndSettle();
    expect(find.textContaining('stays on this phone'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });
}
