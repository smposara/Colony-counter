import 'dart:io';

import 'package:colony_counter/core/classical.dart';
import 'package:colony_counter/core/pipeline.dart';
import 'package:colony_counter/core/plate.dart';
import 'package:colony_counter/core/spots.dart';
import 'package:colony_counter/core/colour.dart';
import 'package:colony_counter/data/plate_record.dart';
import 'package:colony_counter/data/plate_store.dart';
import 'package:colony_counter/data/sample_info.dart';
import 'package:colony_counter/data/storage/storage.dart';
import 'package:colony_counter/ui/format.dart';
import 'package:colony_counter/ui/review_screen.dart';
import 'package:colony_counter/ui/sample_setup_screen.dart';
import 'package:colony_counter/ui/samples_screen.dart';
import 'package:colony_counter/ui/save_sheet.dart';
import 'package:colony_counter/ui/zone_setup_sheet.dart';
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

bool _idle() => find.byType(CircularProgressIndicator).evaluate().isEmpty;

void _phone(WidgetTester tester, {double height = 2340}) {
  tester.view.physicalSize = Size(1080, height);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<PlateStore> _store(WidgetTester tester) async {
  final store = PlateStore(MemoryStorage());
  await tester.runAsync(store.load);
  return store;
}

/// Saves the plate on screen through the save sheet as it is.
Future<void> _save(WidgetTester tester, PlateStore store) async {
  await tester.tap(find.text('Save plate'));
  await tester.pumpAndSettle();
  final save = find.widgetWithText(FilledButton, 'Save');
  await tester.ensureVisible(save);
  await tester.pumpAndSettle();
  await tester.tap(save);
  await _settleReal(tester, () => store.records.isNotEmpty);
}

Future<void> _menu(WidgetTester tester, String item) async {
  await tester.tap(find.byTooltip('Plate type and colours'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(item).last);
  await tester.pumpAndSettle();
}

PlateRecord _record({
  String sampleId = '',
  int dilutionExp = 0,
  double volumeMl = 0.1,
  PlateFormat format = PlateFormat.dish90,
  List<Colony> colonies = const [Colony(500, 500, 5)],
  List<Spot> spots = const [],
}) => PlateRecord(
  id: 'p1',
  createdAt: DateTime(2026, 10, 4),
  imagePath: 'x.jpg',
  imageWidth: 1000,
  imageHeight: 1000,
  plate: const Plate(500, 500, 450),
  colonies: colonies,
  autoCount: colonies.length,
  sampleId: sampleId,
  dilutionExp: dilutionExp,
  volumeMl: volumeMl,
  format: format,
  spots: spots,
);

void main() {
  group('sample save and the default plate type', () {
    testWidgets('a spread sample does not replace a membrane default', (
      tester,
    ) async {
      _phone(tester, height: 6000);
      final store = await _store(tester);
      await tester.runAsync(
        () => store.setDefaults(format: PlateFormat.membrane47),
      );
      await tester.pumpWidget(
        MaterialApp(home: SampleSetupScreen(store: store)),
      );
      await tester.tap(find.text('Spread'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Sample ID'),
        'Soil-1',
      );
      await tester.tap(find.text('Save sample'));
      await tester.pumpAndSettle();
      expect(store.sampleInfo('Soil-1').format, PlateFormat.dish90);
      expect(store.defaultFormat, PlateFormat.membrane47);
    });

    testWidgets('a dish size picked for a new sample is remembered', (
      tester,
    ) async {
      _phone(tester, height: 6000);
      final store = await _store(tester);
      await tester.pumpWidget(
        MaterialApp(home: SampleSetupScreen(store: store)),
      );
      await tester.tap(find.text('90 mm dish'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('150 mm dish').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Sample ID'),
        'Big-1',
      );
      await tester.tap(find.text('Save sample'));
      await tester.pumpAndSettle();
      expect(store.defaultFormat, PlateFormat.dish150);
    });
  });

  group('undo of the plate type toggles', () {
    Future<PlateStore> open(WidgetTester tester) async {
      _phone(tester);
      final store = await _store(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: ReviewScreen(
            store: store,
            photo: File('test/fixtures/sparse.jpg').readAsBytesSync(),
          ),
        ),
      );
      await _settleReal(tester, _idle);
      return store;
    }

    testWidgets('undoing "Drop plate" makes a whole plate again', (
      tester,
    ) async {
      final store = await open(tester);
      await _menu(tester, 'Drop plate');
      expect(find.text('Drops'), findsOneWidget);
      await tester.tap(find.byTooltip('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('Drops'), findsNothing);
      await _save(tester, store);
      final plate = store.records.single;
      expect(plate.isDropPlate, isFalse);
      expect(plate.volumeMl, store.defaultVolumeMl);
    });

    testWidgets('undoing a colour mode restores the previous one', (
      tester,
    ) async {
      final store = await open(tester);
      await _menu(tester, 'Colours: Blue / white');
      expect(find.text('Colour'), findsOneWidget);
      await tester.tap(find.byTooltip('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('Colour'), findsNothing);
      await _save(tester, store);
      expect(store.records.single.colourMode, ColourMode.none);
    });

    testWidgets('a drop plate with every drop deleted is a whole plate', (
      tester,
    ) async {
      _phone(tester);
      final bytes = File('test/fixtures/sparse.jpg').readAsBytesSync();
      final result = countPhoto(bytes);
      final store = PlateStore(MemoryStorage());
      final record = await tester.runAsync(() async {
        await store.load();
        final r = PlateRecord(
          id: 'drops',
          createdAt: DateTime(2026),
          imagePath: await store.savePhoto(bytes, 'drops'),
          imageWidth: result.imageWidth,
          imageHeight: result.imageHeight,
          plate: result.plate,
          colonies: result.colonies,
          autoCount: result.count,
          volumeMl: 0.01,
          spots: [Spot(result.plate.cx, result.plate.cy, 60)],
        );
        await store.upsert(r);
        return r;
      });
      await tester.pumpWidget(
        MaterialApp(
          home: ReviewScreen(store: store, record: record),
        ),
      );
      await _settleReal(tester, () => find.text('Drops').evaluate().isNotEmpty);
      final chip = find.textContaining(RegExp(r'^1: '));
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete drop'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      final save = find.widgetWithText(FilledButton, 'Save');
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await _settleReal(tester, () => !store.records.single.isDropPlate);
      final plate = store.records.single;
      expect(plate.isDropPlate, isFalse);
      expect(plate.volumeMl, store.defaultVolumeMl);
    });
  });

  testWidgets('zone setup keeps a replicate set by hand', (tester) async {
    _phone(tester);
    final store = await _store(tester);
    ZoneSetupChoice? got;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  got = await showZoneSetupSheet(context, store),
              child: const Text('setup'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('setup'));
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.add));
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(find.text('3'), findsOneWidget);
    // Typing the experiment and organism afterwards keeps it.
    await tester.enterText(find.byType(TextField).at(1), 'S. aureus');
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(2), 'Extracts');
    await tester.pump();
    expect(find.text('3'), findsOneWidget);
    await tester.tap(find.text('From gallery'));
    await tester.pumpAndSettle();
    expect(got!.setup.experiment, 'Extracts');
    expect(got!.setup.replicate, 3);
  });

  testWidgets('a drop plate chip leaves TNTC drops out, with a warning', (
    tester,
  ) async {
    _phone(tester, height: 6000);
    final store = await _store(tester);
    final info = SampleInfo(
      sampleId: 'D1',
      method: PlatingMethod.drop,
      dilutions: const [4],
      replicates: 1,
    );
    await tester.runAsync(() async {
      await store.upsertSample(info);
      await store.upsert(
        _record(
          sampleId: 'D1',
          dilutionExp: 4,
          volumeMl: 0.01,
          colonies: [
            for (var i = 0; i < 3; i++) Colony(300.0 + i * 5, 500, 2),
            for (var i = 0; i < 40; i++) Colony(690.0 + i % 8 * 3, 500, 2),
          ],
          spots: const [
            Spot(300, 500, 40, dilutionExp: 4),
            Spot(700, 500, 40, dilutionExp: 4, tntc: true),
          ],
        ),
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        home: SampleDetailScreen(store: store, sampleId: 'D1'),
      ),
    );
    await tester.pump();
    final chip = find.widgetWithText(ActionChip, '10⁻⁴: 3');
    expect(chip, findsOneWidget);
    expect(
      find.descendant(
        of: chip,
        matching: find.byIcon(Icons.warning_amber_rounded),
      ),
      findsOneWidget,
    );
  });

  group('colony photo banner', () {
    test('a membrane plate is reported per 100 mL, like the app', () {
      final r = _record(
        volumeMl: 100,
        format: PlateFormat.membrane47,
        colonies: [for (var i = 0; i < 50; i++) Colony(i.toDouble(), 0, 2)],
      );
      expect(plateBannerCfu(r, 50, null), '${sciValue(50)} CFU/100 mL');
      final plan = SampleInfo(
        sampleId: 'W1',
        method: PlatingMethod.membrane,
        format: PlateFormat.membrane47,
        dilutions: const [0],
        volumeMl: 100,
      );
      expect(plateBannerCfu(r, 50, plan), '${sciValue(50)} CFU/100 mL');
      final dish = _record(dilutionExp: 4, volumeMl: 0.1);
      expect(plateBannerCfu(dish, 12, null), '${sciValue(1.2e6)} CFU/mL');
    });

    test('a Thai sample ID is left out rather than drawn as ????', () {
      expect(bannerSampleId('Lake-A'), 'Lake-A');
      expect(bannerSampleId(''), 'Unlabelled');
      expect(bannerSampleId('ตัวอย่าง-1'), isNull);
    });
  });

  group('save sheet and a sample planned for another plate type', () {
    testWidgets('a membrane plate cannot join a spread sample', (tester) async {
      _phone(tester, height: 6000);
      final store = await _store(tester);
      await tester.runAsync(
        () => store.upsertSample(
          SampleInfo(sampleId: 'S1', dilutions: const [4], replicates: 1),
        ),
      );
      await tester.runAsync(
        () => store.upsertSample(
          SampleInfo(
            sampleId: 'W1',
            method: PlatingMethod.membrane,
            format: PlateFormat.membrane47,
            dilutions: const [0],
            replicates: 1,
            volumeMl: 100,
          ),
        ),
      );
      final draft = _record(
        volumeMl: 100,
        format: PlateFormat.membrane47,
        colonies: [for (var i = 0; i < 50; i++) Colony(i * 4.0, 500, 2)],
      );
      PlateRecord? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => saved = await showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (_) => SaveSheet(store: store, draft: draft),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final id = find.widgetWithText(TextField, 'Sample ID');
      final save = find.widgetWithText(FilledButton, 'Save');

      await tester.enterText(id, 'S1');
      await tester.pump();
      expect(
        find.textContaining('S1 is planned as Spread / pour plate'),
        findsOneWidget,
      );
      expect(find.textContaining('47 mm membrane filter'), findsWidgets);
      expect(tester.widget<FilledButton>(save).onPressed, isNull);

      // A membrane sample fits.
      await tester.enterText(id, 'W1');
      await tester.pump();
      expect(find.textContaining('is planned as'), findsNothing);
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(saved?.sampleId, 'W1');
      expect(saved?.volumeMl, 100);
    });
  });
}
