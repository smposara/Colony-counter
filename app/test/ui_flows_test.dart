import 'package:colony_counter/core/classical.dart';
import 'package:colony_counter/core/plate.dart';
import 'package:colony_counter/data/plate_record.dart';
import 'package:colony_counter/data/plate_store.dart';
import 'package:colony_counter/data/sample_info.dart';
import 'package:colony_counter/data/storage/storage.dart';
import 'package:colony_counter/main.dart';
import 'package:colony_counter/ui/sample_setup_screen.dart';
import 'package:colony_counter/ui/samples_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

var _id = 0;

PlateRecord _plate(String sample, int count, int dilutionExp, int replicate) => PlateRecord(
  id: '${_id++}',
  createdAt: DateTime(2026, 10, 4, 9, _id),
  imagePath: 'p$_id.jpg',
  imageWidth: 1000,
  imageHeight: 1000,
  plate: const Plate(500, 500, 420),
  colonies: [for (var i = 0; i < count; i++) Colony(i.toDouble(), 0, 4)],
  autoCount: count,
  sampleId: sample,
  dilutionExp: dilutionExp,
  replicate: replicate,
);

Future<PlateStore> _store(WidgetTester tester) async {
  final store = PlateStore(MemoryStorage());
  await tester.runAsync(store.load);
  return store;
}

/// A phone-width screen tall enough that nothing needs scrolling.
void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 6000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('setting up a sample creates its plan', (tester) async {
    _phone(tester);
    final store = await _store(tester);
    await tester.pumpWidget(MaterialApp(home: SampleSetupScreen(store: store)));

    await tester.enterText(find.widgetWithText(TextField, 'Sample ID'), 'Lake-A');
    await tester.enterText(find.widgetWithText(TextField, 'Condition'), 'Control');
    final save = find.text('Save sample');
    await tester.tap(save);
    await tester.pumpAndSettle();

    final info = store.sampleInfo('Lake-A');
    expect(store.hasPlan('Lake-A'), isTrue);
    expect(info.condition, 'Control');
    expect(info.dilutions, [4, 5, 6]);
    expect(info.replicates, 3);
    expect(info.slots.length, 9);
  });

  testWidgets('sample detail shows replicate stats and the next plate', (tester) async {
    _phone(tester);
    final store = await _store(tester);
    await tester.runAsync(() async {
      await store.upsertSample(SampleInfo(sampleId: 'S1', dilutions: [4, 5], replicates: 2));
      await store.upsert(_plate('S1', 120, 4, 1));
      await store.upsert(_plate('S1', 100, 4, 2));
    });
    await tester.pumpWidget(MaterialApp(home: SampleDetailScreen(store: store, sampleId: 'S1')));
    await tester.pump();

    // R1 = 1.2e7, R2 = 1.0e7 → mean 1.1e7, n = 2.
    expect(find.text('1.1 × 10⁷ CFU/mL'), findsOneWidget);
    expect(find.textContaining('n = 2 replicates'), findsOneWidget);
    expect(find.textContaining('log₁₀ CFU/mL 7.04 ± 0.06'), findsOneWidget);
    final next = find.text('Photograph 10⁻⁵ · R1');
    expect(find.text('10⁻⁴ · R1: 120'), findsOneWidget);
    expect(next, findsOneWidget);
  });

  testWidgets('compare tab: log reduction vs control over time', (tester) async {
    _phone(tester);
    final store = await _store(tester);
    await tester.runAsync(() async {
      for (final (id, cond, t, count, d) in [
        ('C0', 'Control', 0.0, 100, 5),
        ('C4', 'Control', 4.0, 120, 5),
        ('T0', 'Treated', 0.0, 100, 5),
        ('T4', 'Treated', 4.0, 120, 2), // 1.2e5 vs 1.2e8 → 3 log
      ]) {
        await store.upsertSample(
          SampleInfo(sampleId: id, experiment: 'Kill test', condition: cond, timeH: t, dilutions: [d], replicates: 1),
        );
        await store.upsert(_plate(id, count, d, 1));
      }
    });
    await tester.pumpWidget(ColonyCounterApp(store: store));
    await tester.tap(find.text('Compare'));
    await tester.pumpAndSettle();

    expect(find.text('log₁₀ CFU/mL over time'), findsOneWidget);
    expect(find.text('Reduction vs Control'), findsOneWidget);
    expect(find.text('3.00'), findsOneWidget); // 4 h
    expect(find.text('0.00'), findsOneWidget); // 0 h
    expect(find.text('99.90 %'), findsOneWidget);
  });
}
