import 'dart:io';
import 'dart:typed_data';

import 'package:colony_counter/core/classical.dart';
import 'package:colony_counter/core/plate.dart';
import 'package:colony_counter/core/zones.dart';
import 'package:colony_counter/data/export.dart';
import 'package:colony_counter/data/plate_record.dart';
import 'package:colony_counter/data/plate_store.dart';
import 'package:colony_counter/data/storage/storage.dart';
import 'package:colony_counter/data/zone_record.dart';
import 'package:flutter_test/flutter_test.dart';

const _plate = Plate(500, 500, 450);

ZoneMark _mark(double x, double y, double mm, {String label = ''}) => ZoneMark(
  x: x,
  y: y,
  diskRadiusPx: 30,
  radiusPx: mm / 2 / 0.1,
  diameterMm: mm,
  autoDiameterMm: mm,
  confidence: 0.9,
  label: label,
);

ZoneRecord _record(
  String id, {
  List<ZoneMark>? marks,
  String experiment = 'Extracts',
  int replicate = 1,
}) => ZoneRecord(
  id: id,
  createdAt: DateTime(2026, 10, 9, 9, replicate),
  imagePath: '$id.jpg',
  imageWidth: 1000,
  imageHeight: 1000,
  plate: _plate,
  mmPerPx: 0.1,
  marks: marks ?? [_mark(500, 200, 18, label: 'EtOH')],
  experiment: experiment,
  organism: 'S. aureus',
  replicate: replicate,
);

PlateRecord _colonyPlate(String id) => PlateRecord(
  id: id,
  createdAt: DateTime(2026, 10, 9),
  imagePath: '$id.jpg',
  imageWidth: 1000,
  imageHeight: 1000,
  plate: _plate,
  colonies: const [Colony(10, 10, 3)],
  autoCount: 1,
  sampleId: 'S1',
);

void main() {
  group('Zone records', () {
    test('round-trip through JSON, edits and all', () {
      final r = _record(
        'z1',
        marks: [
          _mark(
            500,
            200,
            18.4,
            label: 'EtOH',
          ).copyWith(diameterMm: 19.4, opened: true),
          ZoneMark(
            x: 300,
            y: 600,
            diskRadiusPx: 30,
            radiusPx: double.nan,
            diameterMm: double.nan,
            autoDiameterMm: double.nan,
            flags: const ['unmeasured'],
          ),
          _mark(700, 600, 6.2).copyWith(noZone: true),
        ],
      ).copyWith(panel: 'Set A', notes: 'lid off');
      final back = ZoneRecord.fromJson(r.toJson());
      expect(back.marks, hasLength(3));
      expect(back.marks[0].diameterMm, 19.4);
      expect(back.marks[0].autoDiameterMm, 18.4);
      expect(back.marks[0].edited, isTrue);
      expect(back.marks[0].opened, isTrue);
      expect(back.marks[1].measured, isFalse);
      expect(back.marks[1].lowConfidence, isTrue);
      expect(back.marks[2].noZone, isTrue);
      expect(back.marks[2].reportedMm(6), 6);
      expect(back.panel, 'Set A');
      expect(back.notes, 'lid off');
      expect(back.assay, ZoneAssay.disk);
      expect(back.checked, isFalse); // the unmeasured disk was not opened
      final opened = back.copyWith(
        marks: [for (final m in back.marks) m.copyWith(opened: true)],
      );
      expect(opened.checked, isTrue);
    });

    test('whole mm on screen, 0.1 mm kept', () {
      final m = _mark(0, 0, 18.5);
      expect(m.roundedMm(6), 19);
      expect(_mark(0, 0, 18.49).roundedMm(6), 18);
      expect(m.reportedMm(6), 18.5);
    });

    test('built from a measured golden plate', () {
      final bytes = File('test/fixtures/zones_reflected.jpg').readAsBytesSync();
      final res = measureZonesInPhoto((
        bytes,
        const ZoneOptions(format: PlateFormat.dish90),
      ));
      final r = ZoneRecord.fromResult(
        res,
        id: 'z9',
        imagePath: 'z9.jpg',
        createdAt: DateTime(2026, 10, 9),
        labels: const ['A', 'B', 'C'],
      );
      expect(r.marks, hasLength(res.zones.length));
      expect([for (final m in r.marks.take(3)) m.label], ['A', 'B', 'C']);
      // The scale the zones were measured at, so mm = 2 r × scale.
      for (final m in r.marks.where((m) => m.diameterMm.isFinite)) {
        expect(m.diameterMm, closeTo(2 * m.radiusPx * r.mmPerPx, 0.05));
        expect(m.edited, isFalse);
      }
      final back = ZoneRecord.fromJson(r.toJson());
      expect(
        back.marks.map((m) => m.diameterMm).toList(),
        r.marks.map((m) => m.diameterMm).toList(),
      );
    });
  });

  group('Labels', () {
    test('clockwise from 12 o’clock, a centre disk last', () {
      final marks = [
        _mark(500, 500, 10), // centre
        _mark(800, 500, 10), // 3 o'clock
        _mark(500, 150, 10), // 12 o'clock
        _mark(200, 500, 10), // 9 o'clock
        _mark(500, 850, 10), // 6 o'clock
      ];
      final out = assignLabels(marks, _plate, const ['a', 'b', 'c', 'd', 'e']);
      expect(
        [for (final m in out) (m.x, m.y, m.label)],
        [
          (500.0, 150.0, 'a'),
          (800.0, 500.0, 'b'),
          (500.0, 850.0, 'c'),
          (200.0, 500.0, 'd'),
          (500.0, 500.0, 'e'),
        ],
      );
    });

    test('a disk just left of 12 o’clock still comes first', () {
      final out = assignLabels(
        [
          _mark(800, 500, 10), // 3 o'clock
          _mark(480, 150, 10), // 12, a little to the left
          _mark(200, 500, 10), // 9 o'clock
        ],
        _plate,
        const ['a', 'b', 'c'],
      );
      expect(
        [for (final m in out) (m.x, m.label)],
        [(480.0, 'a'), (800.0, 'b'), (200.0, 'c')],
      );
    });

    test('more disks than labels keep their own', () {
      final out = assignLabels(
        [_mark(500, 150, 10, label: 'x'), _mark(800, 500, 10, label: 'y')],
        _plate,
        const ['a'],
      );
      expect([for (final m in out) m.label], ['a', 'y']);
    });
  });

  group('Summary', () {
    test('mean ± SD per experiment, organism and label', () {
      final rows = summariseZones([
        _record(
          'a',
          replicate: 1,
          marks: [
            _mark(0, 0, 18, label: 'EtOH'),
            _mark(0, 0, 6.3, label: 'DMSO').copyWith(noZone: true),
            _mark(0, 0, 25, label: ''),
          ],
        ),
        _record(
          'b',
          replicate: 2,
          marks: [
            _mark(0, 0, 20, label: 'EtOH'),
            _mark(0, 0, 6.1, label: 'DMSO').copyWith(noZone: true),
          ],
        ),
        _record(
          'c',
          experiment: 'Other',
          marks: [_mark(0, 0, 30, label: 'EtOH')],
        ),
      ]);
      expect(rows.map((r) => (r.experiment, r.label)).toList(), [
        ('Extracts', 'DMSO'),
        ('Extracts', 'EtOH'),
        ('Other', 'EtOH'),
      ]);
      final etoh = rows[1];
      expect(etoh.n, 2);
      expect(etoh.mean, closeTo(19, 1e-9));
      expect(etoh.sd, closeTo(1.4142, 1e-4));
      // No zone counts as the 6 mm disk.
      expect(rows[0].values, [6.0, 6.0]);
      expect(rows[2].sd.isNaN, isTrue);
    });
  });

  group('Store and backup', () {
    test('zone plates and panels are stored and reloaded', () async {
      final backend = MemoryStorage();
      final store = PlateStore(backend);
      await store.load();
      await store.upsertZone(_record('z1'));
      await store.upsertZone(_record('z2', replicate: 2));
      await store.savePanel(const ZonePanel('Set A', ['EtOH', 'Hex', 'Aq']));
      await store.savePanel(const ZonePanel('Set A', ['EtOH', 'Hex']));
      final again = PlateStore(backend);
      await again.load();
      expect(again.zoneRecords.map((r) => r.id), ['z2', 'z1']);
      expect(again.zonePanels.single.labels, ['EtOH', 'Hex']);
      expect(again.records, isEmpty);
      expect(again.zoneExperiments(), ['Extracts']);
      await again.deleteZone(again.zoneRecords.first);
      expect(again.zoneRecords.single.id, 'z1');
    });

    test('a store from before zones loads with none', () async {
      final backend = MemoryStorage();
      final store = PlateStore(backend);
      await store.load();
      await store.upsert(_colonyPlate('p1'));
      final again = PlateStore(backend);
      await again.load();
      expect(again.records, hasLength(1));
      expect(again.zoneRecords, isEmpty);
      expect(again.zonePanels, isEmpty);
    });

    test('backup and restore with colony and zone plates mixed', () async {
      final store = PlateStore(MemoryStorage());
      await store.load();
      final photo = Uint8List.fromList([1, 2, 3]);
      final zphoto = Uint8List.fromList([9, 8, 7]);
      await store.savePhoto(photo, 'p1');
      await store.upsert(_colonyPlate('p1'));
      await store.savePhoto(zphoto, 'z1');
      await store.upsertZone(_record('z1'));
      await store.savePanel(const ZonePanel('Set A', ['EtOH']));
      final zip = await buildBackup(store);

      // Into an empty store: everything comes back.
      final fresh = PlateStore(MemoryStorage());
      await fresh.load();
      final sum = await restoreBackup(fresh, zip);
      expect(sum.platesAdded, 2);
      expect(fresh.records.single.id, 'p1');
      expect(fresh.zoneRecords.single.id, 'z1');
      expect(fresh.zonePanels.single.name, 'Set A');
      expect(await fresh.readPhotoPath('z1.jpg'), zphoto);

      // Into a store that already has them: nothing doubles.
      final again = await restoreBackup(fresh, zip);
      expect(again.platesAdded, 0);
      expect(again.platesSkipped, 2);
      expect(fresh.zoneRecords, hasLength(1));
      expect(fresh.zonePanels, hasLength(1));
    });

    test('a zone photo never overwrites a colony plate photo', () async {
      final store = PlateStore(MemoryStorage());
      await store.load();
      final colonyPhoto = Uint8List.fromList([1, 1, 1]);
      await store.savePhoto(colonyPhoto, 'x');
      await store.upsert(
        PlateRecord.fromJson({
          ..._colonyPlate('p1').toJson(),
          'image': 'x.jpg',
        }),
      );
      final zone = ZoneRecord.fromJson({
        ..._record('z1').toJson(),
        'image': 'x.jpg',
      });
      await store.importAll(
        const [],
        const [],
        (_) async => Uint8List.fromList([2, 2, 2]),
        zonePlates: [zone],
      );
      expect(store.zoneRecords.single.imagePath, 'x_2.jpg');
      expect(await store.readPhotoPath('x.jpg'), colonyPhoto);
    });
  });
}
