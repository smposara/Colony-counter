import 'dart:io';

import 'package:colony_counter/core/classical.dart';
import 'package:colony_counter/core/plate.dart';
import 'package:colony_counter/core/zones.dart';
import 'package:colony_counter/data/plate_record.dart';
import 'package:colony_counter/data/plate_store.dart';
import 'package:colony_counter/data/sample_info.dart';
import 'package:colony_counter/data/storage/storage.dart';
import 'package:colony_counter/data/zone_record.dart';
import 'package:colony_counter/ui/about_screen.dart';
import 'package:colony_counter/ui/accuracy_screen.dart';
import 'package:colony_counter/ui/home_screen.dart';
import 'package:colony_counter/ui/sample_setup_screen.dart';
import 'package:colony_counter/ui/samples_screen.dart';
import 'package:colony_counter/ui/timelapse_screen.dart';
import 'package:colony_counter/ui/zone_calibration_screen.dart';
import 'package:colony_counter/ui/zone_results_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A tablet or desktop screen of [width] × [height] logical pixels.
void _screen(WidgetTester tester, double width, double height) {
  tester.view.physicalSize = Size(width * 2, height * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

void _landscapeTablet(WidgetTester tester) => _screen(tester, 1280, 800);

/// A CustomPaint drawn by a painter class named [name] (private ones too).
Finder _painted(String name) => find.byWidgetPredicate(
  (w) => w is CustomPaint && w.painter.runtimeType.toString() == name,
);

/// [target] lies within a column 720 wide in the middle of the screen.
void _expectReadable(
  WidgetTester tester,
  Finder target, {
  double screen = 1280,
}) {
  expect(target, findsWidgets);
  final r = tester.getRect(target.first);
  expect(r.left, greaterThanOrEqualTo((screen - 720) / 2), reason: '$target');
  expect(r.right, lessThanOrEqualTo((screen + 720) / 2), reason: '$target');
}

/// The page's list (not a text field's scrollable).
Finder get _page => find
    .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
    .first;

var _n = 0;

PlateRecord _rec({
  List<Colony> colonies = const [Colony(500, 500, 5)],
  bool verified = false,
  String seriesId = '',
  double? hours,
  String imagePath = 'x.jpg',
}) {
  _n++;
  return PlateRecord(
    id: 'r$_n',
    createdAt: DateTime(2026, 10, 4, 8, _n),
    imagePath: imagePath,
    imageWidth: 1000,
    imageHeight: 1000,
    plate: const Plate(500, 500, 450),
    colonies: colonies,
    autoCount: colonies.where((c) => !c.manual).length,
    sampleId: 'S1',
    dilutionExp: 4,
    verified: verified,
    seriesId: seriesId,
    incubationH: hours,
  );
}

Future<PlateStore> _store(
  WidgetTester tester, [
  Future<void> Function(PlateStore store)? fill,
]) async {
  final store = PlateStore(MemoryStorage());
  await tester.runAsync(() async {
    await store.load();
    await store.setDefaults(language: 'en');
    await fill?.call(store);
  });
  return store;
}

final _zonePhoto = File('test/fixtures/zones_reflected.jpg').readAsBytesSync();

Future<void> _settleReal(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 300 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
  }
}

/// The zone calibration wizard at its readings step for a measured plate.
Future<void> _calibrationReadings(WidgetTester tester) async {
  final measured = measureZonesInPhoto((_zonePhoto, const ZoneOptions()));
  final store = await _store(tester, (store) async {
    final name = await store.savePhoto(_zonePhoto, 'zone_p1');
    await store.upsertZone(
      ZoneRecord.fromResult(
        measured,
        id: 'p1',
        imagePath: name,
        createdAt: DateTime.now(),
        experiment: 'Extracts',
        camera: '0',
      ),
    );
  });
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => openZoneCalibration(context, store, wizard: true),
          child: const Text('go'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
  tester
      .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
      .removeCurrentSnackBar();
  await tester.pumpAndSettle();
  final b = find.text('Use a plate I just measured');
  await tester.ensureVisible(b);
  await tester.pumpAndSettle();
  await tester.tap(b);
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining('Extracts ·'));
  await _settleReal(
    tester,
    () => find.byKey(const ValueKey('calZone0')).evaluate().isNotEmpty,
  );
  await tester.pumpAndSettle();
}

void main() {
  group('charts fit on a 1280 × 800 tablet screen', () {
    testWidgets('accuracy scatter chart', (tester) async {
      _landscapeTablet(tester);
      final store = await _store(tester, (store) async {
        await store.upsert(
          _rec(
            verified: true,
            colonies: [
              for (var i = 0; i < 20; i++) Colony(100.0 + i, 500, 5),
              const Colony(100, 600, 5, manual: true),
            ],
          ),
        );
        await store.upsert(_rec(verified: true));
      });
      await tester.pumpWidget(MaterialApp(home: AccuracyScreen(store: store)));
      await tester.pump();
      final chart = _painted('_ScatterPainter');
      expect(chart, findsOneWidget);
      await tester.ensureVisible(chart);
      await tester.pump();
      final r = tester.getRect(chart);
      expect(r.height, lessThanOrEqualTo(380));
      expect(r.top, greaterThanOrEqualTo(0));
      expect(r.bottom, lessThanOrEqualTo(800));
    });

    testWidgets('time-lapse count chart and appearance map', (tester) async {
      _landscapeTablet(tester);
      final photo = File('test/fixtures/empty.jpg').readAsBytesSync();
      final store = await _store(tester, (store) async {
        final name = await store.savePhoto(photo, 'tl');
        await store.upsert(_rec(seriesId: 's', hours: 16, imagePath: name));
        await store.upsert(
          _rec(
            seriesId: 's',
            hours: 24,
            imagePath: name,
            colonies: const [Colony(500, 500, 8), Colony(300, 300, 4)],
          ),
        );
      });
      await tester.pumpWidget(
        MaterialApp(
          home: TimelapseScreen(store: store, seriesId: 's'),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
      final chart = _painted('_LinePainter');
      expect(chart, findsOneWidget);
      expect(tester.getRect(chart).height, lessThanOrEqualTo(380));
      final map = _painted('_AppearancePainter');
      await tester.scrollUntilVisible(map, 300, scrollable: _page);
      expect(map, findsOneWidget);
      final m = tester.getRect(map);
      expect(m.height, lessThanOrEqualTo(480));
      expect(m.width, lessThanOrEqualTo(480));
    });
  });

  group('pushed pages are no wider than 720 on a 1280 × 800 tablet', () {
    testWidgets('new sample', (tester) async {
      _landscapeTablet(tester);
      final store = await _store(tester);
      await tester.pumpWidget(
        MaterialApp(home: SampleSetupScreen(store: store)),
      );
      await tester.pump();
      _expectReadable(tester, find.widgetWithText(TextField, 'Sample ID'));
      final save = find.widgetWithText(FilledButton, 'Save sample');
      await tester.scrollUntilVisible(save, 300, scrollable: _page);
      _expectReadable(tester, save);
    });

    testWidgets('sample detail', (tester) async {
      _landscapeTablet(tester);
      final store = await _store(tester, (store) async {
        await store.upsertSample(
          SampleInfo(sampleId: 'S1', dilutions: const [4, 5], replicates: 1),
        );
      });
      await tester.pumpWidget(
        MaterialApp(
          home: SampleDetailScreen(store: store, sampleId: 'S1'),
        ),
      );
      await tester.pump();
      _expectReadable(
        tester,
        find.ancestor(
          of: find.textContaining('Photograph '),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        ),
      );
    });

    testWidgets('zone calibration wizard', (tester) async {
      _landscapeTablet(tester);
      final store = await _store(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  openZoneCalibration(context, store, wizard: true),
              child: const Text('go'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      _expectReadable(tester, find.text('Check the app against your calliper'));
    });

    testWidgets('zone results', (tester) async {
      _landscapeTablet(tester);
      final store = await _store(tester);
      await tester.pumpWidget(
        MaterialApp(home: ZoneResultsScreen(store: store)),
      );
      await tester.pump();
      _expectReadable(tester, find.byType(DropdownButtonFormField<String>));
    });

    testWidgets('counting accuracy', (tester) async {
      _landscapeTablet(tester);
      final store = await _store(tester);
      await tester.pumpWidget(MaterialApp(home: AccuracyScreen(store: store)));
      await tester.pump();
      _expectReadable(tester, find.byType(Card));
    });

    testWidgets('About', (tester) async {
      _landscapeTablet(tester);
      await tester.pumpWidget(const MaterialApp(home: AboutScreen()));
      await tester.pump();
      _expectReadable(tester, find.byType(ListTile));
    });
  });

  testWidgets('settings sheet is taller than 9/16 on a landscape tablet', (
    tester,
  ) async {
    _screen(tester, 960, 600);
    final store = await _store(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showSettingsSheet(context, store),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final sheet = tester.getRect(
      find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(sheet.height, greaterThan(600 * 9 / 16 + 1));
    expect(sheet.height, lessThanOrEqualTo(600 * 0.9 + 0.01));
    expect(sheet.width, lessThanOrEqualTo(640));
  });

  testWidgets('settings sheet on a phone keeps its 9/16 height', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final store = await _store(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showSettingsSheet(context, store),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byType(BottomSheet)).height,
      closeTo(780 * 9 / 16, 0.01),
    );
  });

  testWidgets('calibration readings: the photo grows on a portrait tablet', (
    tester,
  ) async {
    _screen(tester, 800, 1280);
    await _calibrationReadings(tester);
    final photo = find
        .ancestor(
          of: find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is CalibrationNumbersPainter,
          ),
          matching: find.byType(ColoredBox),
        )
        .first;
    final h = tester.getRect(photo).height;
    expect(h, greaterThan(400));
    expect(h, lessThanOrEqualTo(480));
    // The readings below are no wider than the readable width.
    _expectReadable(
      tester,
      find.byKey(const ValueKey('calSeeResult')),
      screen: 800,
    );
  });
}
