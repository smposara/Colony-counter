import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:colony_counter/core/classical.dart';
import 'package:colony_counter/core/plate.dart';
import 'package:colony_counter/core/stats.dart';
import 'package:colony_counter/data/accuracy.dart';
import 'package:colony_counter/data/examples.dart';
import 'package:colony_counter/data/export.dart';
import 'package:colony_counter/data/export_jobs.dart';
import 'package:colony_counter/data/export_source.dart';
import 'package:colony_counter/data/plate_record.dart';
import 'package:colony_counter/data/plate_store.dart';
import 'package:colony_counter/data/sample_info.dart';
import 'package:colony_counter/data/storage/storage.dart';
import 'package:colony_counter/data/training_export.dart';
import 'package:colony_counter/data/zone_record.dart';
import 'package:colony_counter/l10n/l10n.dart';
import 'package:colony_counter/main.dart';
import 'package:colony_counter/ui/review_screen.dart';
import 'package:colony_counter/ui/sample_setup_screen.dart';
import 'package:colony_counter/ui/save_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final _zip = File(kExamplesAsset).readAsBytesSync();
Future<Uint8List> _load() async => _zip;

const _lake = 'Example – lake water';

Future<PlateStore> _open([StorageBackend? backend]) async {
  final store = PlateStore(backend ?? MemoryStorage());
  await store.load();
  return store;
}

Future<PlateStore> _withExamples() async {
  final store = await _open();
  await addExamples(store, load: _load);
  return store;
}

/// A plate of the user's own (not an example).
PlateRecord _mine(String id, {String sample = '', int dilution = 4}) =>
    PlateRecord(
      id: id,
      createdAt: DateTime(2026, 10, 10),
      imagePath: '$id.jpg',
      imageWidth: 100,
      imageHeight: 100,
      plate: const Plate(50, 50, 40),
      colonies: const [Colony(40, 40, 3), Colony(60, 60, 3)],
      autoCount: 2,
      sampleId: sample,
      dilutionExp: dilution,
      verified: true,
    );

ZoneRecord _myZone() => ZoneRecord(
  id: 'zmine',
  createdAt: DateTime(2026, 10, 10),
  imagePath: 'zone_zmine.jpg',
  imageWidth: 100,
  imageHeight: 100,
  plate: const Plate(50, 50, 40),
  mmPerPx: 0.1,
  marks: const [],
);

Future<void> _saveMine(PlateStore store, PlateRecord r) =>
    store.saveCapture(r, Uint8List.fromList([1, 2, 3]));

Future<void> _loadFonts() async {
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final f in files) {
      loader.addFont(
        Future.value(ByteData.sublistView(File(f).readAsBytesSync())),
      );
    }
    await loader.load();
  }

  const a = 'assets/fonts';
  await family('Roboto', ['$a/Roboto-Regular.ttf', '$a/Roboto-Medium.ttf']);
  await family('IBMPlexSansThai', [
    '$a/IBMPlexSansThai-Regular.ttf',
    '$a/IBMPlexSansThai-Medium.ttf',
  ]);
  await family('ColonySymbols', ['$a/ColonySymbols-Regular.ttf']);
}

final _manifest = jsonDecode(
  utf8.decode(
    ZipDecoder()
            .decodeBytes(_zip)
            .findFile('colony-counter-backup.json')!
            .content
        as List<int>,
  ),
) as Map<String, dynamic>;

void main() {
  group('Example data', () {
    test('the asset restores the whole set, without settings', () async {
      final manifest = _manifest;
      expect(manifest.containsKey('settings'), isFalse);

      final store = await _open();
      await store.setDefaults(language: 'th', theme: 'dark', operator: 'Ann');
      await addExamples(store, load: _load);
      expect(store.records, hasLength(8));
      expect(store.samplePlans, hasLength(5));
      expect(store.zoneRecords, hasLength(1));
      expect(store.records.every((r) => r.isExample), isTrue);
      expect(store.zoneRecords.single.isExample, isTrue);
      expect(store.samplePlans.every((s) => s.isExample), isTrue);
      expect(store.language, 'th');
      expect(store.theme, 'dark');
      expect(store.defaultOperator, 'Ann');
      for (final r in store.records) {
        expect(await store.readPhoto(r), isNotNull, reason: r.id);
      }

      // The lake sample: a real result, 10⁻⁶ R1 next.
      final lake = store.sampleInfo(_lake);
      final plates = store.platesOf(_lake);
      expect(plates, hasLength(4));
      final next = lake.nextSlot(plates)!;
      expect((next.dilutionExp, next.replicate), (6, 1));
      final stats = lake.analyse(plates, store.rule).stats;
      expect(stats.n, 2);
      expect(stats.log10Mean, inInclusiveRange(7, 7.7));

      // The disinfectant set: about 2 log at 2 h.
      ReplicateStats of(String id) =>
          store.sampleInfo(id).analyse(store.platesOf(id), store.rule).stats;
      final r = Reduction(
        of('Example – control 2 h'),
        of('Example – treated 2 h'),
      );
      expect(r.logReduction, closeTo(2, 0.25));
      expect(store.experiments(), contains('Example – disinfectant'));

      // The zone plate: measured and labelled.
      final z = store.zoneRecords.single;
      expect(z.marks, hasLength(6));
      expect(z.marks.map((m) => m.label), contains('Neg'));
    });

    test('the bundled asset loads', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final store = await _open();
      await addExamples(store);
      expect(store.records, hasLength(8));
    });

    test('first launch seeds an empty app once', () async {
      final backend = MemoryStorage();
      var store = await _open(backend);
      await offerExamples(store, load: _load);
      expect(hasExamples(store), isTrue);
      expect(store.examplesOffered, isTrue);

      // Relaunch after removing them: they stay away.
      await removeExamples(store);
      store = await _open(backend);
      expect(store.examplesOffered, isTrue);
      await offerExamples(store, load: _load);
      expect(hasExamples(store), isFalse);
      expect(store.records, isEmpty);
    });

    test('an app with data only remembers the offer', () async {
      final backend = MemoryStorage();
      var store = await _open(backend);
      await store.upsertSample(SampleInfo(sampleId: 'Mine'));
      await offerExamples(store, load: _load);
      expect(hasExamples(store), isFalse);
      store = await _open(backend);
      expect(store.examplesOffered, isTrue);
    });

    test('a failed load never throws', () async {
      final store = await _open();
      await offerExamples(store, load: () async => throw StateError('gone'));
      expect(store.records, isEmpty);
      expect(store.examplesOffered, isTrue);
    });

    test('removing them leaves the user data alone', () async {
      final store = await _withExamples();
      // Mine: a sample in the example experiment, a plate of its own and a
      // zone plate. A plate added to the example lake sample is example data
      // and goes with it.
      await _saveMine(store, _mine('m1', sample: _lake, dilution: 6));
      await store.upsertSample(
        SampleInfo(
          sampleId: 'My control 4 h',
          experiment: 'Example – disinfectant',
          condition: 'Control',
          timeH: 4,
        ),
      );
      await _saveMine(store, _mine('m2', sample: 'My control 4 h'));
      await store.saveZoneCapture(_myZone(), Uint8List.fromList([4]));

      await removeExamples(store);
      expect(store.records.map((r) => r.id).toSet(), {'m2'});
      expect(store.zoneRecords.map((r) => r.id), ['zmine']);
      expect(store.samplePlans.map((s) => s.sampleId).toSet(), {
        'My control 4 h',
      });
      expect(hasExamples(store), isFalse);
      expect(await store.backend.readPhoto('example-lake-e4-r1.jpg'), isNull);
      expect(await store.backend.readPhoto('zone_example-zones.jpg'), isNull);
      expect(await store.backend.readPhoto('m1.jpg'), isNull);
      expect(await store.backend.readPhoto('m2.jpg'), isNotNull);
      expect(await store.backend.readPhoto('zone_zmine.jpg'), isNotNull);

      // Back again, and only once.
      await addExamples(store, load: _load);
      await addExamples(store, load: _load);
      expect(store.records, hasLength(9));
      expect(store.zoneRecords, hasLength(2));
      expect(store.samplePlans, hasLength(6));
      expect(hasExamples(store), isTrue);
    });

    test('exports, accuracy and training data leave them out', () async {
      final store = await _withExamples();
      // Even an example marked as checked does not count.
      await store.upsert(store.records.first.copyWith(verified: true));
      await _saveMine(store, _mine('m1'));
      expect(AccuracyReport(store.records).points.map((p) => p.record.id), [
        'm1',
      ]);
      for (final s in TrainingSelection.values) {
        expect(trainingPlates(store, s).map((r) => r.id), ['m1']);
      }
      final csv = await prepareExport(store);
      for (final text in (csv['files'] as Map).values) {
        expect(text as String, isNot(contains('example')));
      }
      final copy = await _open();
      await restoreBackup(copy, await buildBackup(store));
      expect(copy.records.map((r) => r.id), ['m1']);
      expect(copy.samplePlans, isEmpty);
      expect(copy.zoneRecords, isEmpty);
    });

    test('the reserved IDs are exactly the shipped samples', () {
      expect({
        for (final s in _manifest['samples'] as List)
          (s as Map)['sample_id'] as String,
      }, kExampleSampleIds);
    });

    test('a sample of the user\'s own tagged "example" is not one', () async {
      final store = await _withExamples();
      // E.g. tagged by hand, or from an older backup.
      await store.upsertSample(
        SampleInfo(sampleId: 'Mine', tags: const [kExampleTag]),
      );
      await _saveMine(store, _mine('m1', sample: 'Mine'));
      expect(store.sampleInfo('Mine').isExample, isFalse);
      final m1 = store.records.firstWhere((r) => r.id == 'm1');
      expect(isExamplePlate(store, m1), isFalse);
      final csv = await prepareExport(store);
      expect((csv['files'] as Map)['samples.csv'] as String, contains('Mine'));
      final copy = await _open();
      await restoreBackup(copy, await buildBackup(store));
      expect(copy.samplePlans.map((s) => s.sampleId), ['Mine']);
      await removeExamples(store);
      expect(store.samplePlans.map((s) => s.sampleId), ['Mine']);
      expect(store.records.map((r) => r.id), ['m1']);
    });

    test('a plate added to an example sample is example data', () async {
      final store = await _withExamples();
      await _saveMine(store, _mine('m1', sample: _lake, dilution: 6));
      await _saveMine(store, _mine('m2'));
      final m1 = store.records.firstWhere((r) => r.id == 'm1');
      expect(isExamplePlate(store, m1), isTrue);
      expect(AccuracyReport.of(store).points.map((p) => p.record.id), ['m2']);
      for (final s in TrainingSelection.values) {
        expect(trainingPlates(store, s).map((r) => r.id), ['m2']);
      }
      final csv = await prepareExport(store);
      for (final text in (csv['files'] as Map).values) {
        expect(text as String, isNot(contains('Example')));
      }
      final copy = await _open();
      await restoreBackup(copy, await buildBackup(store));
      expect(copy.records.map((r) => r.id), ['m2']);

      // Removed with the example, so nothing left in the app disagrees with
      // the export.
      await removeExamples(store);
      expect(store.records.map((r) => r.id), ['m2']);
      expect(hasExamples(store), isFalse);
    });

    test('first launch adds nothing if data arrives while loading', () async {
      final store = await _open();
      final zip = Completer<Uint8List>();
      final offered = offerExamples(store, load: () => zip.future);
      // The user saves a plate before the examples are read.
      await _saveMine(store, _mine('m1'));
      zip.complete(_zip);
      await offered;
      expect(store.records.map((r) => r.id), ['m1']);
      expect(store.samplePlans, isEmpty);
      expect(store.zoneRecords, isEmpty);
      expect(store.examplesOffered, isTrue);
    });

    test(
      'a backup restores its settings on a phone with only examples',
      () async {
        final source = await _open();
        await source.setDefaults(language: 'th');
        await _saveMine(source, _mine('m1'));
        final zip = await buildBackup(source);
        final phone = await _withExamples();
        await restoreBackup(phone, zip);
        expect(phone.language, 'th');
      },
    );
  });

  group('Example data on screen', () {
    Future<PlateStore> pumpApp(
      WidgetTester tester, {
      String language = 'en',
    }) async {
      // A 360 × 780 phone with the app's fonts (the test font is wider).
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.runAsync(_loadFonts);
      final store = (await tester.runAsync(() async {
        final store = await _withExamples();
        await store.setDefaults(language: language);
        return store;
      }))!;
      addTearDown(
        () => setCurrentStrings(lookupAppLocalizations(const Locale('en'))),
      );
      await tester.pumpWidget(ColonyCounterApp(store: store));
      await tester.pump();
      return store;
    }

    Future<void> settle(WidgetTester tester, bool Function() done) async {
      for (var i = 0; i < 100 && !done(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 500));
    }

    testWidgets('banner and badges, and Remove removes them', (tester) async {
      final store = await pumpApp(tester);
      expect(find.byKey(const ValueKey('examplesBanner')), findsOneWidget);
      expect(find.text(tr.examplesBanner), findsOneWidget);
      expect(find.text(tr.examplesBadge), findsWidgets);
      final banner = tester.getRect(
        find.byKey(const ValueKey('examplesBanner')),
      );
      expect(banner.height, lessThan(56));

      // Every tab: the banner, and badges on samples and the zone plate.
      await tester.tap(find.text(tr.homeSamples).last);
      await tester.pumpAndSettle();
      expect(find.text(tr.examplesBanner), findsOneWidget);
      expect(find.text(tr.examplesBadge), findsWidgets);
      await tester.tap(find.text(tr.homeCompare).last);
      await tester.pumpAndSettle();
      expect(find.text(tr.examplesBanner), findsOneWidget);
      // Compare opens on the time-kill set.
      expect(find.text('Example – disinfectant'), findsWidgets);
      expect(find.text('Treated'), findsWidgets);
      await tester.tap(find.text(tr.homeZones).last);
      await tester.pumpAndSettle();
      expect(find.text(tr.examplesBanner), findsOneWidget);
      expect(find.text(tr.examplesBadge), findsOneWidget);

      await tester.tap(find.text(tr.examplesRemove));
      await tester.pumpAndSettle();
      expect(find.text(tr.examplesRemoveTitle), findsOneWidget);
      await tester.tap(find.text(tr.examplesRemoveAction));
      await settle(tester, () => !hasExamples(store));
      expect(store.records, isEmpty);
      expect(store.zoneRecords, isEmpty);
      expect(find.text(tr.examplesBanner), findsNothing);
      expect(find.text(tr.examplesBadge), findsNothing);

      // Settings offers them again.
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(tr.homeSettings));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text(tr.settingsAddExamples),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text(tr.settingsAddExamples));
      await settle(tester, () => hasExamples(store));
      expect(store.records, hasLength(8));
      expect(find.text(tr.settingsRemoveExamples), findsOneWidget);
    });

    testWidgets('New sample like this from an example is the user\'s own', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final store = (await tester.runAsync(_withExamples))!;
      await tester.pumpWidget(
        MaterialApp(
          home: SampleSetupScreen(
            store: store,
            template: store.sampleInfo(_lake),
          ),
        ),
      );
      final id = tester
          .widget<TextField>(find.widgetWithText(TextField, tr.setupSampleId))
          .controller!
          .text;
      expect(id, 'lake water-2');
      await tester.scrollUntilVisible(
        find.text(tr.setupSave),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text(tr.setupSave));
      await tester.pumpAndSettle();
      final copy = store.sampleInfo(id);
      expect(store.hasPlan(id), isTrue);
      expect(copy.tags, isNot(contains(kExampleTag)));
      expect(copy.experiment, 'lake survey');
      expect(copy.dilutions, store.sampleInfo(_lake).dilutions);
      await tester.runAsync(() => removeExamples(store));
      expect(store.samplePlans.map((s) => s.sampleId), [id]);
    });

    testWidgets('saving into an example sample says it joins it', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 6000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final store = (await tester.runAsync(_withExamples))!;
      Future<void> open(String sample) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SaveSheet(
                key: ValueKey(sample),
                store: store,
                draft: _mine('d', sample: sample, dilution: 6),
                fixedSample: true,
              ),
            ),
          ),
        );
        await tester.pump();
      }

      await open(_lake);
      expect(find.text(tr.examplesSaveNote), findsOneWidget);
      await open('Mine');
      expect(find.text(tr.examplesSaveNote), findsNothing);
    });

    testWidgets('plates added to examples do not make a check due', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final store = (await tester.runAsync(() async {
        final store = await _withExamples();
        // A check every 2nd plate: an unchecked plate of the user's own
        // would make this one due, one in an example sample does not.
        await store.setDefaults(accuracyCheckEvery: 2);
        await _saveMine(
          store,
          _mine('m1', sample: _lake, dilution: 6).copyWith(verified: false),
        );
        return store;
      }))!;
      await tester.pumpWidget(
        MaterialApp(
          home: ReviewScreen(
            store: store,
            photo: File('test/fixtures/sparse.jpg').readAsBytesSync(),
          ),
        ),
      );
      for (var i = 0; i < 150; i++) {
        if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }
      expect(find.text('automatic'), findsOneWidget);
      expect(find.text(tr.reviewAccuracyCheck), findsNothing);
    });

    testWidgets('Compare opens on the user\'s own experiment', (tester) async {
      final store = await pumpApp(tester);
      await tester.runAsync(
        () => store.upsertSample(
          SampleInfo(sampleId: 'Mine', experiment: 'Zeta trial'),
        ),
      );
      await tester.pump();
      await tester.tap(find.text(tr.homeCompare).last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('Zeta trial')), findsOneWidget);
    });

    testWidgets('the banner stays slim in Thai', (tester) async {
      await pumpApp(tester, language: 'th');
      expect(find.text('นี่คือข้อมูลสาธิตสำหรับลองใช้งาน'), findsOneWidget);
      expect(find.text('สาธิต'), findsWidgets);
      final banner = tester.getRect(
        find.byKey(const ValueKey('examplesBanner')),
      );
      expect(banner.height, lessThan(56));
    });
  });
}
