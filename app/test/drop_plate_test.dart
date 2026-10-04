import 'dart:convert';
import 'dart:io';

import 'package:colony_counter/core/colour.dart';
import 'package:colony_counter/data/plate_store.dart';
import 'package:colony_counter/data/sample_info.dart';
import 'package:colony_counter/data/storage/storage.dart';
import 'package:colony_counter/ui/photo_flow.dart';
import 'package:colony_counter/ui/review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _settleReal(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
  }
}

/// A drop plate (all dilutions on one plate) with blue and white colonies,
/// opened from a sample plan: drops are found, labelled with the plan's
/// dilutions, and colonies are split into blue and white.
void main() {
  testWidgets('drop plate from a plan: drops, dilutions, blue/white, CFU/mL', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final label = jsonDecode(File('test/fixtures/drops.json').readAsStringSync()) as Map<String, dynamic>;
    final drops = [for (final d in label['drops'] as List) d as Map<String, dynamic>];
    final store = PlateStore(MemoryStorage());
    await tester.runAsync(store.load);
    final info = SampleInfo(
      sampleId: 'D1',
      method: PlatingMethod.drop,
      dilutions: const [4, 5, 6, 7],
      replicates: 1,
      dropLayout: DropLayout.dilutions,
      colourMode: ColourMode.blueWhite,
    );
    await tester.runAsync(() => store.upsertSample(info));

    await tester.pumpWidget(
      MaterialApp(
        home: ReviewScreen(
          store: store,
          photo: File('test/fixtures/drops.jpg').readAsBytesSync(),
          preset: PlatePreset(info: info, slot: info.slots.first),
        ),
      ),
    );
    await _settleReal(tester, () => find.byType(CircularProgressIndicator).evaluate().isEmpty);

    // Drops with colonies are found in reading order and get the plan's dilutions;
    // the empty 10⁻⁷ drop has nothing to detect, so the user would add it by hand.
    expect(find.textContaining('1: 10⁻⁴ R1'), findsOneWidget);
    expect(find.textContaining('2: 10⁻⁵ R1'), findsOneWidget);
    expect(find.textContaining('3: 10⁻⁶ R1'), findsOneWidget);
    expect(find.textContaining('Blue '), findsOneWidget);

    await tester.tap(find.text('Save plate'));
    await tester.pumpAndSettle();
    final save = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await _settleReal(tester, () => store.records.isNotEmpty);

    final plate = store.records.single;
    expect(plate.sampleId, 'D1');
    expect(plate.isDropPlate, isTrue);
    expect(plate.volumeMl, closeTo(0.01, 1e-12));
    final counts = [for (final o in plate.observations()) o.count.count];
    expect(counts.length, 3);
    for (var i = 0; i < 3; i++) {
      final want = drops[i]['count'] as int;
      expect((counts[i] - want).abs(), lessThanOrEqualTo(2), reason: 'drop ${i + 1}');
    }
    final blue = drops.fold<int>(0, (s, d) => s + (d['blue'] as int));
    expect((plate.classCounts[1] - blue).abs(), lessThanOrEqualTo(2));

    // All three drops are in the 3–30 range and pool into one replicate value.
    final result = store.sampleInfo('D1').analyse(store.platesOf('D1'), store.rule);
    final expected = counts.reduce((a, b) => a + b) / (0.01 * (1e-4 + 1e-5 + 1e-6));
    expect(result.stats.n, 1);
    expect(result.stats.mean, closeTo(expected, expected * 0.02));
  });
}
