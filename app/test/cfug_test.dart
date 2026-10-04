import 'package:colony_counter/core/calculator.dart';
import 'package:colony_counter/core/classical.dart';
import 'package:colony_counter/core/plate.dart';
import 'package:colony_counter/data/export.dart';
import 'package:colony_counter/data/plate_record.dart';
import 'package:colony_counter/data/plate_store.dart';
import 'package:colony_counter/data/sample_info.dart';
import 'package:colony_counter/data/storage/storage.dart';
import 'package:colony_counter/ui/format.dart';
import 'package:colony_counter/ui/samples_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

PlateRecord _plate(String sample, int count, int dilutionExp, int rep) =>
    PlateRecord(
      id: '$sample-$dilutionExp-$rep',
      createdAt: DateTime(2026, 10, 4, 10, rep),
      imagePath: 'x.jpg',
      imageWidth: 1000,
      imageHeight: 1000,
      plate: const Plate(500, 500, 450),
      colonies: [for (var i = 0; i < count; i++) Colony(i.toDouble(), 0, 4)],
      autoCount: count,
      sampleId: sample,
      dilutionExp: dilutionExp,
      replicate: rep,
    );

void main() {
  test('solid sample 25 g in 225 mL: CFU/g with no correction', () {
    final info = SampleInfo(
      sampleId: 'Cheese',
      solid: true,
      dilutions: const [2, 3],
      replicates: 1,
    );
    expect(info.initialDilution, 10);
    expect((info.unitLabel, info.unitFactor), ('CFU/g', 1.0));
    // 150 colonies on the 10⁻² plate (0.1 mL) = 1.5 × 10⁵ CFU/g.
    final res = info.analyse([
      _plate('Cheese', 150, 2, 1),
      _plate('Cheese', 14, 3, 1),
    ], CountingRule.fdaBam);
    expect(res.stats.mean * info.unitFactor, closeTo(1.5e5, 1));
  });

  test('a 1:5 initial suspension is corrected', () {
    final info = SampleInfo(
      sampleId: 'Soil',
      solid: true,
      sampleWeightG: 10,
      diluentMl: 40,
    );
    expect(info.initialDilution, 5);
    expect(info.unitFactor, 0.5);
    final back = SampleInfo.fromJson(info.toJson());
    expect(
      (back.isSolid, back.sampleWeightG, back.diluentMl),
      (true, 10.0, 40.0),
    );
    // Liquid and membrane samples ignore the solid settings.
    expect(SampleInfo(sampleId: 'L').unitLabel, 'CFU/mL');
    expect(
      SampleInfo(
        sampleId: 'M',
        solid: true,
        method: PlatingMethod.membrane,
      ).unitLabel,
      'CFU/100 mL',
    );
  });

  test('sample CSV reports the sample\'s own unit', () async {
    final store = PlateStore(MemoryStorage());
    await store.load();
    await store.upsertSample(
      SampleInfo(
        sampleId: 'Soil',
        solid: true,
        sampleWeightG: 10,
        diluentMl: 40,
        dilutions: const [2],
        replicates: 1,
      ),
    );
    await store.upsert(_plate('Soil', 100, 2, 1));
    final lines = samplesCsv(store).trim().split('\n');
    final row = Map.fromIterables(lines[0].split(','), lines[1].split(','));
    expect(row['unit'], 'CFU/g');
    expect(double.parse(row['mean_in_unit']!), closeTo(1e5 * 0.5, 1e-6));
    expect(double.parse(row['mean_cfu_per_ml']!), closeTo(1e5, 1e-6));
    expect(row['sample_g'], '10.0');
  });

  testWidgets('the Samples list shows results in each sample\'s unit', (tester) async {
    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final store = PlateStore(MemoryStorage());
    await tester.runAsync(() async {
      await store.load();
      await store.upsertSample(SampleInfo(sampleId: 'Soil', solid: true, sampleWeightG: 10, diluentMl: 40, dilutions: const [2], replicates: 1));
      await store.upsert(_plate('Soil', 100, 2, 1));
      await store.upsertSample(SampleInfo(sampleId: 'Tap', method: PlatingMethod.membrane, dilutions: const [0], replicates: 1, volumeMl: 100));
      await store.upsert(PlateRecord.fromJson({..._plate('Tap', 45, 0, 1).toJson(), 'volume_ml': 100, 'id': 'tap'}));
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SamplesTab(store: store))));
    await tester.pump();
    expect(find.text('5.0 × 10⁴'), findsOneWidget); // CFU/g, corrected for 1:5
    expect(find.text('4.5 × 10¹'), findsOneWidget); // 45 CFU/100 mL
    expect(find.textContaining('log₁₀ 1.65'), findsOneWidget);
  });

  test('only the exponent is superscripted', () {
    expect(prettySci('4.5 × 10^1 CFU/100 mL'), '4.5 × 10¹ CFU/100 mL');
    expect(prettySci('est. 1.2 × 10^-3 CFU/g'), 'est. 1.2 × 10⁻³ CFU/g');
  });
}
