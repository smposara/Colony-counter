import 'package:colony_counter/core/classical.dart';
import 'package:colony_counter/core/plate.dart';
import 'package:colony_counter/data/plate_record.dart';
import 'package:colony_counter/data/plate_store.dart';
import 'package:colony_counter/data/sample_info.dart';
import 'package:colony_counter/data/storage/storage.dart';
import 'package:colony_counter/ui/accuracy_screen.dart';
import 'package:colony_counter/ui/home_screen.dart';
import 'package:colony_counter/ui/sample_setup_screen.dart';
import 'package:colony_counter/ui/samples_screen.dart';
import 'package:colony_counter/ui/save_sheet.dart';
import 'package:colony_counter/ui/timelapse_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Android 15 phone, edge to edge: 360 × 780 dp with a 48 dp navigation bar
/// drawn over the bottom of the app.
const _bar = 48.0;
const _height = 780.0;

void _edgeToEdgePhone(WidgetTester tester) {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(360 * 3, _height * 3);
  tester.view.padding = const FakeViewPadding(bottom: _bar * 3);
  tester.view.viewPadding = const FakeViewPadding(bottom: _bar * 3);
  addTearDown(tester.view.reset);
}

/// Scrolls [target]'s scrollable to the end and checks [target] sits above
/// the navigation bar.
Future<void> _expectClearOfNavBar(WidgetTester tester, Finder target) async {
  // The page's main (vertical) scrollable; lazy lists build the target only
  // once it is scrolled into view.
  final scrollable = find.byWidgetPredicate(
    (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
  );
  for (var i = 0; i < 5; i++) {
    // The tallest one: multi-line text fields are scrollables too.
    final page = scrollable.evaluate().reduce(
      (a, b) => a.size!.height >= b.size!.height ? a : b,
    );
    final position = (page as StatefulElement).state as ScrollableState;
    position.position.jumpTo(position.position.maxScrollExtent);
    await tester.pump();
  }
  expect(target, findsWidgets);
  expect(tester.getRect(target.last).bottom, lessThanOrEqualTo(_height - _bar));
}

PlateRecord _plate(String sample) => PlateRecord(
  id: 'p$sample',
  createdAt: DateTime(2026, 10, 4),
  imagePath: 'x.jpg',
  imageWidth: 1000,
  imageHeight: 1000,
  plate: const Plate(500, 500, 450),
  colonies: const [Colony(500, 500, 5)],
  autoCount: 1,
  sampleId: sample,
  dilutionExp: 4,
  verified: true,
  seriesId: 's',
  incubationH: 24,
);

Future<PlateStore> _store(WidgetTester tester) async {
  final store = PlateStore(MemoryStorage());
  await tester.runAsync(() async {
    await store.load();
    await store.upsertSample(SampleInfo(sampleId: 'S1', dilutions: const [4], replicates: 1));
    await store.upsert(_plate('S1'));
  });
  return store;
}

void main() {
  testWidgets('sample setup: Save sample clears the navigation bar', (tester) async {
    _edgeToEdgePhone(tester);
    final store = await _store(tester);
    await tester.pumpWidget(MaterialApp(home: SampleSetupScreen(store: store)));
    await _expectClearOfNavBar(tester, find.text('Save sample'));
  });

  testWidgets('save sheet: Save clears the navigation bar', (tester) async {
    _edgeToEdgePhone(tester);
    final store = await _store(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => SaveSheet(store: store, draft: store.records.single),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await _expectClearOfNavBar(tester, find.widgetWithText(FilledButton, 'Save'));
  });

  testWidgets('settings sheet ends above the navigation bar', (tester) async {
    _edgeToEdgePhone(tester);
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
    final last = find.byType(DropdownButtonFormField<PlateFormat>);
    await _expectClearOfNavBar(tester, last);
  });

  testWidgets('long pages leave room for the navigation bar', (tester) async {
    _edgeToEdgePhone(tester);
    final store = await _store(tester);
    for (final page in <Widget>[
      SampleDetailScreen(store: store, sampleId: 'S1'),
      AccuracyScreen(store: store),
      TimelapseScreen(store: store, seriesId: 's'),
    ]) {
      await tester.pumpWidget(MaterialApp(home: page));
      await tester.pump();
      final list = tester.widget<ListView>(find.byType(ListView).first);
      expect(
        (list.padding! as EdgeInsets).bottom,
        greaterThanOrEqualTo(_bar),
        reason: '${page.runtimeType}',
      );
    }
  });
}
