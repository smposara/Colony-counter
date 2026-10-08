import 'dart:convert';
import 'dart:io';

import 'package:colony_counter/core/drop_stats.dart';
import 'package:colony_counter/core/spots.dart';
import 'package:colony_counter/data/plate_store.dart';
import 'package:colony_counter/data/sample_info.dart';
import 'package:colony_counter/data/storage/storage.dart';
import 'package:colony_counter/ui/photo_flow.dart';
import 'package:colony_counter/ui/review_screen.dart';
import 'package:colony_counter/ui/sample_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _settleReal(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 300 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
  }
}

Map<String, dynamic> _label(String name) =>
    jsonDecode(File('test/fixtures/$name.json').readAsStringSync())
        as Map<String, dynamic>;

Future<PlateStore> _open(
  WidgetTester tester,
  SampleInfo info,
  String fixture,
) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final store = PlateStore(MemoryStorage());
  await tester.runAsync(store.load);
  await tester.runAsync(() => store.upsertSample(info));
  await tester.pumpWidget(
    MaterialApp(
      home: ReviewScreen(
        store: store,
        photo: File('test/fixtures/$fixture.jpg').readAsBytesSync(),
        preset: PlatePreset(info: info, slot: info.slots.first),
      ),
    ),
  );
  await _settleReal(
    tester,
    () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
  );
  return store;
}

Future<void> _save(WidgetTester tester, PlateStore store) async {
  await tester.tap(find.text('Save plate'));
  await tester.pumpAndSettle();
  final save = find.widgetWithText(FilledButton, 'Save');
  await tester.ensureVisible(save);
  await tester.pumpAndSettle();
  await tester.tap(save);
  await _settleReal(tester, () => store.records.isNotEmpty);
}

void main() {
  testWidgets('rows layout: every planned drop, empty ones included', (
    tester,
  ) async {
    final label = _label('drops_grid4x3');
    final info = SampleInfo(
      sampleId: 'G1',
      method: PlatingMethod.drop,
      dilutions: const [4, 5, 6, 7],
      replicates: 2,
      dropLayout: DropLayout.dilutions,
      dropArrangement: DropArrangement.grid,
      dropsPerDilution: 3,
      dropPitchMm: 12,
    );
    final store = await _open(tester, info, 'drops_grid4x3');

    // 12 drops, three of each dilution, all on this plate's replicate (R1).
    for (final d in ['10⁻⁴', '10⁻⁵', '10⁻⁶', '10⁻⁷']) {
      expect(find.textContaining(RegExp('^\\d+: $d R1 ')), findsNWidgets(3));
    }

    // Leave the first 10⁻⁵ drop out.
    final chip = find.textContaining(RegExp(r'^\d+: 10⁻⁵ R1 ')).first;
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave this drop out'));
    await tester.pumpAndSettle();
    expect(find.text('Why'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.textContaining(' · left out'), findsOneWidget);

    await _save(tester, store);
    final plate = store.records.single;
    expect(plate.spots, hasLength(12));
    expect(
      [for (final s in plate.spots) s.position]..sort(),
      List.generate(12, (i) => i),
    );
    final out = plate.spots.where((s) => s.isExcluded).toList();
    expect(out, hasLength(1));
    expect(out.single.excluded, DropExclusion.splash);
    expect(out.single.dilutionExp, 5);

    // The saved drops match the Python reference on the same photo, and the
    // left-out drop is not in the result.
    final py = [
      for (final d in (label['python'] as Map)['drops'] as List)
        d as Map<String, dynamic>,
    ];
    for (final s in plate.spots) {
      final p = py.reduce(
        (a, b) =>
            (s.cx - a['x']) * (s.cx - a['x']) +
                    (s.cy - a['y']) * (s.cy - a['y']) <=
                (s.cx - b['x']) * (s.cx - b['x']) +
                    (s.cy - b['y']) * (s.cy - b['y'])
            ? a
            : b,
      );
      expect(s.dilutionExp, p['dilution_exp']);
      expect(s.tntc, p['confluent']);
      if (!s.tntc) {
        expect(
          countInSpot(s, plate.colonies),
          closeTo(p['count'] as int, 2),
          reason: 'drop at ${s.cx}, ${s.cy}',
        );
      }
    }
    expect(plate.observations(), hasLength(11));
  });

  testWidgets('ring layout: labels can be turned by one drop', (tester) async {
    final info = SampleInfo(
      sampleId: 'R1',
      method: PlatingMethod.drop,
      dilutions: const [3, 4, 5, 6, 7, 8, 9, 10],
      replicates: 1,
      dropLayout: DropLayout.dilutions,
      dropArrangement: DropArrangement.sectors,
    );
    await _open(tester, info, 'drops_sectors8');
    for (var d = 3; d <= 10; d++) {
      expect(
        find.textContaining(RegExp(': 10⁻${_sup(d)} R1 ')),
        findsOneWidget,
      );
    }
    String labelOf(int i) =>
        (tester.widget<Text>(find.textContaining(RegExp('^${i + 1}: ')))).data!;
    final before = [for (var i = 0; i < 8; i++) labelOf(i).split(' · ').first];

    await tester.tap(find.byTooltip('Plate type and colours'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Turn labels by one drop'));
    await tester.pumpAndSettle();
    final after = [for (var i = 0; i < 8; i++) labelOf(i).split(' · ').first];
    // Every drop has a new dilution; together they are the same eight.
    for (var i = 0; i < 8; i++) {
      expect(after[i].split(': ').last, isNot(before[i].split(': ').last));
    }
    expect(
      {for (final a in after) a.split(': ').last},
      {for (final b in before) b.split(': ').last},
    );
  });

  testWidgets('setup: choosing rows shows the layout and saves it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final store = PlateStore(MemoryStorage());
    await tester.runAsync(store.load);
    SampleInfo? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              saved = await Navigator.of(context).push<SampleInfo>(
                MaterialPageRoute(
                  builder: (_) => SampleSetupScreen(store: store),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final drop = find.text('Drop');
    await tester.ensureVisible(drop);
    await tester.tap(drop);
    await tester.pumpAndSettle();
    // New drop samples start with the ring.
    expect(find.text('Ring'), findsOneWidget);
    expect(find.textContaining('12 o\'clock'), findsOneWidget);

    final all = find.text('All dilutions on one plate, one drop each');
    await tester.ensureVisible(all);
    await tester.tap(all);
    await tester.pumpAndSettle();
    final rows = find.text('Rows');
    await tester.ensureVisible(rows);
    await tester.tap(rows);
    await tester.pumpAndSettle();
    expect(find.text('Drops of each dilution'), findsOneWidget);
    expect(find.text('Distance between drops'), findsOneWidget);
    expect(
      find.bySemanticsLabel('How the drops sit on each plate'),
      findsOneWidget,
    );
    final plus = find.byIcon(Icons.add).last;
    await tester.ensureVisible(plus);
    await tester.tap(plus);
    await tester.pumpAndSettle();

    // Counting window and calculation.
    final to = find.widgetWithText(TextField, 'To');
    await tester.ensureVisible(to);
    await tester.enterText(find.widgetWithText(TextField, 'From'), '5');
    await tester.enterText(to, '50');
    final first = find.text('First countable');
    await tester.ensureVisible(first);
    await tester.tap(first);
    await tester.pumpAndSettle();
    expect(find.textContaining('least diluted dilution'), findsOneWidget);

    final save = find.text('Save sample');
    await tester.scrollUntilVisible(
      save,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(saved, isNotNull);
    expect(saved!.dropArrangement, DropArrangement.grid);
    expect(saved!.dropLayout, DropLayout.dilutions);
    expect(saved!.dropsPerDilution, 2);
    expect(saved!.dropsPerPlate, saved!.dilutions.length * 2);
    expect(saved!.dropWindow, (5, 50));
    expect(saved!.dropMode, DropMode.first);
  });
}

String _sup(int d) =>
    d.toString().split('').map((c) => '⁰¹²³⁴⁵⁶⁷⁸⁹'[int.parse(c)]).join();
