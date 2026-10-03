import 'dart:io';

import 'package:colony_counter/core/calculator.dart';
import 'package:colony_counter/core/classical.dart';
import 'package:colony_counter/core/plate.dart';
import 'package:colony_counter/data/plate_record.dart';
import 'package:colony_counter/data/plate_store.dart';
import 'package:flutter_test/flutter_test.dart';

PlateRecord _record(
  String id,
  int count,
  int dilutionExp, {
  String sample = 'S1',
}) => PlateRecord(
  id: id,
  createdAt: DateTime(2026, 10, 3, 12, int.parse(id)),
  imagePath: '$id.jpg',
  imageWidth: 1000,
  imageHeight: 1000,
  plate: const Plate(500, 500, 420),
  colonies: [for (var i = 0; i < count; i++) Colony(i.toDouble(), 0, 5)],
  autoCount: count,
  sampleId: sample,
  dilutionExp: dilutionExp,
);

void main() {
  test('record JSON round trip keeps edits', () {
    final r = _record('1', 3, 4).copyWith(
      colonies: const [
        Colony(1, 2, 3),
        Colony(4, 5, 6, n: 3),
        Colony(7, 8, 9, manual: true),
      ],
      notes: 'lid fogged',
      spreader: true,
    );
    final back = PlateRecord.fromJson(r.toJson());
    expect(back.count, 5);
    expect(back.added, 1);
    expect(back.notes, 'lid fogged');
    expect(back.spreader, isTrue);
    expect(back.dilution, closeTo(1e-4, 1e-12));
    expect(back.plate.radius, 420);
  });

  test('CSV pools plates of the same sample', () {
    final csv = recordsToCsv([
      _record('1', 120, 3),
      _record('2', 15, 4),
    ], CountingRule.fdaBam);
    final lines = csv.trim().split('\n');
    expect(lines.first, startsWith('plate_id,date,sample_id'));
    expect(lines.length, 3);
    // Only the 10^-3 plate is in 25–250: 120 / (0.1 × 1e-3) = 1.2e6.
    expect(lines[1], contains(',1200000.0,'));
  });

  test('store persists records and settings', () async {
    final dir = await Directory.systemTemp.createTemp('cc_store');
    addTearDown(() => dir.delete(recursive: true));
    final store = PlateStore(dir);
    await store.load();
    await store.upsert(_record('1', 10, 2));
    await store.upsert(_record('2', 30, 1, sample: 'S2'));
    await store.setRule(CountingRule.iso7218);

    final again = PlateStore(dir);
    await again.load();
    expect(again.records.map((r) => r.id), ['2', '1']); // newest first
    expect(again.rule, CountingRule.iso7218);
    expect(again.samples().keys.toSet(), {'S1', 'S2'});

    await again.delete(again.records.first);
    expect(again.records.length, 1);
  });
}
