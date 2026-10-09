import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:colony_counter/core/annotate.dart';
import 'package:colony_counter/core/plate.dart';
import 'package:colony_counter/core/zones.dart';
import 'package:colony_counter/data/export.dart';
import 'package:colony_counter/data/plate_store.dart';
import 'package:colony_counter/data/storage/storage.dart';
import 'package:colony_counter/data/zone_record.dart';
import 'package:colony_counter/main.dart';
import 'package:colony_counter/ui/home_screen.dart';
import 'package:colony_counter/ui/zone_results_screen.dart';
import 'package:colony_counter/ui/zone_review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

const _plate = Plate(500, 500, 450);

ZoneMark _mark(
  double mm, {
  String label = '',
  double x = 500,
  double y = 200,
}) => ZoneMark(
  x: x,
  y: y,
  diskRadiusPx: 30,
  radiusPx: mm / 2 / 0.1,
  diameterMm: mm,
  autoDiameterMm: mm,
  confidence: 0.876,
  label: label,
);

ZoneRecord _record(
  String id,
  List<ZoneMark> marks, {
  String experiment = 'Extracts',
  String organism = 'S. aureus',
  int replicate = 1,
}) => ZoneRecord(
  id: id,
  createdAt: DateTime(2026, 10, 9, 9, replicate),
  imagePath: '$id.jpg',
  imageWidth: 1000,
  imageHeight: 1000,
  plate: _plate,
  mmPerPx: 0.1,
  marks: marks,
  experiment: experiment,
  organism: organism,
  replicate: replicate,
);

/// Rows of a CSV as maps by header (no quoted commas in these tests).
List<Map<String, String>> _rows(String csv) {
  final lines = const LineSplitter().convert(csv);
  final head = lines.first.split(',');
  return [for (final l in lines.skip(1)) Map.fromIterables(head, l.split(','))];
}

Future<PlateStore> _filled() async {
  final store = PlateStore(MemoryStorage());
  await store.load();
  await store.upsertZone(
    _record('a', [
      _mark(18.44, label: 'EtOH').copyWith(diameterMm: 19.04, opened: true),
      _mark(6.3, label: 'DMSO', x: 800, y: 500).copyWith(noZone: true),
      ZoneMark(
        x: 200,
        y: 500,
        diskRadiusPx: 30,
        radiusPx: double.nan,
        diameterMm: double.nan,
        autoDiameterMm: double.nan,
        flags: const ['unmeasured'],
        label: 'Hex',
      ),
    ]),
  );
  await store.upsertZone(
    _record('b', [
      _mark(21, label: 'EtOH'),
      _mark(6.1, label: 'DMSO').copyWith(noZone: true),
    ], replicate: 2),
  );
  await store.upsertZone(
    _record(
      'c',
      [_mark(25, label: 'Amp')],
      experiment: 'Controls',
      organism: 'E. coli',
      replicate: 3,
    ),
  );
  return store;
}

void main() {
  group('zones.csv', () {
    test('one row per zone, oldest plate first, as reported', () async {
      final store = await _filled();
      final rows = _rows(zonesCsv(store));
      expect(rows, hasLength(6));
      final first = rows.first;
      expect(first['plate_id'], 'a');
      expect(first['date'], '2026-10-09');
      expect(first['experiment'], 'Extracts');
      expect(first['assay'], 'disk');
      expect(first['disk_or_well_mm'], '6.0');
      expect(first['zone'], '1');
      expect(first['label'], 'EtOH');
      expect(first['diameter_mm'], '19.0');
      expect(first['diameter_mm_rounded'], '19');
      expect(first['auto_diameter_mm'], '18.4');
      expect(first['edited'], 'true');
      expect(first['confidence'], '0.88');
      expect(first['x_mm'], '0.0');
      expect(first['y_mm'], '-30.0');
      expect(first['image'], 'a.jpg');
      // No zone: reported as the 6 mm disk.
      expect(rows[1]['no_zone'], 'true');
      expect(rows[1]['diameter_mm'], '6.0');
      expect(rows[1]['diameter_mm_rounded'], '6');
      // Not measured: empty, with its flag.
      expect(rows[2]['diameter_mm'], '');
      expect(rows[2]['diameter_mm_rounded'], '');
      expect(rows[2]['flags'], 'unmeasured');
      expect(rows.last['plate_id'], 'c');
    });

    test('a label with a comma is quoted', () async {
      final store = PlateStore(MemoryStorage());
      await store.load();
      await store.upsertZone(_record('q', [_mark(12, label: 'Amp, 10 µg')]));
      expect(zonesCsv(store), contains('"Amp, 10 µg"'));
    });
  });

  group('zone_summary.csv', () {
    test('mean ± SD per experiment, organism and label', () async {
      final store = await _filled();
      final rows = _rows(zoneSummaryCsv(store));
      expect(
        [for (final r in rows) (r['experiment'], r['label'], r['n'])],
        [
          ('Controls', 'Amp', '1'),
          ('Extracts', 'DMSO', '2'),
          ('Extracts', 'EtOH', '2'),
        ],
      );
      final etoh = rows.last;
      expect(etoh['mean_mm'], '20.02');
      expect(etoh['sd_mm'], '1.39');
      expect(rows.first['sd_mm'], ''); // one plate: no SD
      expect(rows[1]['mean_mm'], '6.0');
    });

    test(
      'the backup carries both CSVs only when there are zone plates',
      () async {
        final store = await _filled();
        final zip = ZipDecoder().decodeBytes(await buildBackup(store));
        final names = [for (final f in zip.files) f.name];
        expect(names, containsAll(['zones.csv', 'zone_summary.csv']));
        final empty = PlateStore(MemoryStorage());
        await empty.load();
        final none = ZipDecoder().decodeBytes(await buildBackup(empty));
        expect([
          for (final f in none.files) f.name,
        ], isNot(contains('zones.csv')));
      },
    );
  });

  group('Annotated photo', () {
    test('zones are drawn in green, unsure ones in amber', () {
      final bytes = File('test/fixtures/zones_reflected.jpg').readAsBytesSync();
      final res = measureZonesInPhoto((bytes, const ZoneOptions()));
      final r = ZoneRecord.fromResult(
        res,
        id: 'z',
        imagePath: 'z.jpg',
        createdAt: DateTime(2026, 10, 9),
        labels: const ['DMSO', 'EtOH'],
        experiment: 'Extracts',
      );
      final zones = zoneAnnotations(r);
      expect(zones, hasLength(6));
      expect(zones[0].text, '6 mm (no zone) DMSO');
      expect(zones[0].radiusPx.isNaN, isTrue);
      expect(zones[1].text, '11 mm EtOH');
      expect(zones[2].text, '17 mm 3');
      final header = zoneAnnotationHeader(r);
      expect(header[0], 'Extracts - Rep 1');
      expect(header[1], startsWith('Disks 6 mm - 6 zones'));
      expect(header[2], contains('no S/I/R'));

      final jpeg = annotatePhoto(
        AnnotationJob(
          photo: bytes,
          plate: r.plate,
          colonies: const [],
          zones: zones,
          header: header,
          rimFraction: 1,
        ),
      );
      final out = img.decodeJpg(jpeg)!;
      expect(out.width, 1200);
      // On the 11.5 mm zone circle, right of its centre: green.
      final m = r.marks[1];
      final px = out.getPixel((m.x + m.radiusPx).round(), m.y.round());
      expect(px.g, greaterThan(180));
      expect(px.r, lessThan(160));
      // The banner is dark.
      expect(out.getPixel(600, 10).r, lessThan(80));
    });
  });

  group('Results screen', () {
    Future<void> phone(WidgetTester tester, {bool small = false}) async {
      tester.view.physicalSize = Size(1080, small ? 1920 : 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
    }

    testWidgets('a table and bars per organism, by experiment', (tester) async {
      await phone(tester);
      final store = (await tester.runAsync(_filled))!;
      await tester.pumpWidget(
        MaterialApp(home: ZoneResultsScreen(store: store)),
      );
      await tester.pumpAndSettle();
      // The newest plate is in Controls.
      expect(find.text('E. coli'), findsOneWidget);
      expect(find.text('Amp'), findsOneWidget);
      expect(find.text('25.0'), findsOneWidget);
      expect(find.text('1 plate'), findsOneWidget);

      await tester.tap(find.text('Controls'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Extracts').last);
      await tester.pumpAndSettle();
      expect(find.text('S. aureus'), findsOneWidget);
      expect(find.text('2 plates'), findsOneWidget);
      expect(find.text('20.0 ± 1.4'), findsOneWidget);
      expect(find.text('6.0 ± 0.0'), findsOneWidget);
      expect(find.textContaining('does not interpret'), findsOneWidget);
    });

    testWidgets('from the Zones tab, with the zone CSV export', (tester) async {
      await phone(tester);
      final store = (await tester.runAsync(_filled))!;
      await tester.pumpWidget(MaterialApp(home: HomeScreen(store: store)));
      await tester.tap(find.text('Zones').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text('Export zone CSVs'), findsOneWidget);
      await tester.tapAt(const Offset(10, 400));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Results'));
      await tester.pumpAndSettle();
      expect(find.byType(ZoneResultsScreen), findsOneWidget);
    });

    testWidgets('Thai on a small phone fits', (tester) async {
      await phone(tester, small: true);
      final store = (await tester.runAsync(_filled))!;
      await tester.runAsync(() => store.setDefaults(language: 'th'));
      await tester.pumpWidget(ColonyCounterApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.text('โซนยับยั้ง').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('ผลการวัด'));
      await tester.pumpAndSettle();
      expect(find.text('ค่าเฉลี่ย ± SD (มม.)'), findsOneWidget);
    });
  });
}
