import 'dart:convert';
import 'dart:io';

import 'package:colony_counter/core/plate.dart';
import 'package:colony_counter/data/plate_record.dart';
import 'package:colony_counter/data/plate_store.dart';
import 'package:colony_counter/data/sample_info.dart';
import 'package:colony_counter/data/storage/storage.dart';
import 'package:colony_counter/ui/photo_flow.dart';
import 'package:colony_counter/ui/review_screen.dart';
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

/// An E. coli/coliform film photographed for a sample plan: counted with the
/// film counter, both results shown, saved with its grid, and reported per
/// result through the CFU calculator.
void main() {
  testWidgets('EC film from a plan: results, gas mode, save, CFU/mL', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final python = _label('film_ec')['python'] as Map<String, dynamic>;
    final ecoli = python['counts']['ecoli'] as int;
    final coliform = python['counts']['coliform'] as int;

    final store = PlateStore(MemoryStorage());
    await tester.runAsync(store.load);
    final info = SampleInfo(
      sampleId: 'F1',
      method: PlatingMethod.film,
      format: PlateFormat.filmEc,
      dilutions: const [1],
      replicates: 1,
      volumeMl: 1,
    );
    await tester.runAsync(() => store.upsertSample(info));

    await tester.pumpWidget(
      MaterialApp(
        home: ReviewScreen(
          store: store,
          photo: File('test/fixtures/film_ec.jpg').readAsBytesSync(),
          preset: PlatePreset(info: info, slot: info.slots.first),
        ),
      ),
    );
    await _settleReal(
      tester,
      () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );

    expect(find.textContaining('E. coli '), findsOneWidget);
    expect(find.textContaining('Coliforms '), findsOneWidget);
    expect(find.text('Gas'), findsOneWidget);
    expect(find.text('Kind'), findsOneWidget);
    await tester.tap(find.text('Gas'));
    await tester.pump();
    expect(find.textContaining('gas bubble'), findsOneWidget);

    await tester.tap(find.text('Save plate'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Petrifilm 15–150'), findsOneWidget);
    final save = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await _settleReal(tester, () => store.records.isNotEmpty);

    final plate = store.records.single;
    expect(plate.isFilm, isTrue);
    expect(plate.filmType, 'ec');
    expect(plate.filmGrid, isNotNull);
    expect(plate.volumeMl, 1);
    final tally = plate.filmTally;
    expect(tally.counts['ecoli'], closeTo(ecoli, 1));
    expect(tally.counts['coliform'], closeTo(coliform, 1));

    // Saved and loaded again: film type, grid and gas marks survive.
    final again = PlateRecord.fromJson(
      jsonDecode(jsonEncode(plate.toJson())) as Map<String, dynamic>,
    );
    expect(again.filmTally.counts, tally.counts);
    expect(again.colonies.where((c) => c.gas).length, greaterThan(0));

    // Per result through the calculator: 1 mL of the 10⁻¹ dilution.
    final res = info.analyse(store.platesOf('F1'), store.rule);
    final resColi = info.analyse(
      store.platesOf('F1'),
      store.rule,
      result: 'coliform',
    );
    expect(
      res.perReplicate[1]!.value,
      closeTo(tally.counts['ecoli']! * 10, 10),
    );
    expect(
      resColi.perReplicate[1]!.value,
      closeTo(tally.counts['coliform']! * 10, 10),
    );
  });

  testWidgets('a dish photo counted as a film warns that no grid was found', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final store = PlateStore(MemoryStorage());
    await tester.runAsync(store.load);
    final info = SampleInfo(
      sampleId: 'G1',
      method: PlatingMethod.film,
      format: PlateFormat.filmAc,
      dilutions: const [1],
      replicates: 1,
      volumeMl: 1,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ReviewScreen(
          store: store,
          photo: File('test/fixtures/sparse.jpg').readAsBytesSync(),
          preset: PlatePreset(info: info, slot: info.slots.first),
        ),
      ),
    );
    await _settleReal(
      tester,
      () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );
    expect(find.textContaining('printed grid was not found'), findsOneWidget);
    // The banner says it; no extra chip.
    expect(find.text('Grid not found'), findsNothing);
  });

  testWidgets('crowded film: tap a grid square to leave it out', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final store = PlateStore(MemoryStorage());
    await tester.runAsync(store.load);
    final info = SampleInfo(
      sampleId: 'C1',
      method: PlatingMethod.film,
      format: PlateFormat.filmAc,
      dilutions: const [1],
      replicates: 1,
      volumeMl: 1,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ReviewScreen(
          store: store,
          photo: File('test/fixtures/film_ac_crowded.jpg').readAsBytesSync(),
          preset: PlatePreset(info: info, slot: info.slots.first),
        ),
      ),
    );
    await _settleReal(
      tester,
      () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );
    expect(find.textContaining('estimated from 8'), findsOneWidget);
    await tester.tap(find.text('Squares'));
    await tester.pump();
    expect(find.textContaining('leave it out'), findsOneWidget);

    // Tap the middle of the first complete square (image → screen).
    final python =
        jsonDecode(
              File('test/fixtures/film_ac_crowded.json').readAsStringSync(),
            )['python']
            as Map<String, dynamic>;
    expect(python['squares_used'], 8);
    // The photo's own detector (the viewer has others): it handles long-press.
    final photo = find.byWidgetPredicate(
      (w) => w is GestureDetector && w.onLongPressStart != null,
    );
    final box = tester.renderObject<RenderBox>(photo);
    final state = tester.state(find.byType(ReviewScreen));
    // ignore: avoid_dynamic_calls
    final centre = (state as dynamic).debugSquareCentre(0) as Offset;
    await tester.tapAt(box.localToGlobal(centre));
    await tester.pump();
    expect(find.textContaining('estimated from 7'), findsOneWidget);
    expect(find.textContaining('1 square left out'), findsOneWidget);

    // Undo puts it back.
    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    expect(find.textContaining('estimated from 8'), findsOneWidget);
  });
}
