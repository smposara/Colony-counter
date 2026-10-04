import 'dart:convert';
import 'dart:io';

import 'package:colony_counter/data/plate_store.dart';
import 'package:colony_counter/data/storage/storage_io.dart';
import 'package:colony_counter/main.dart';
import 'package:colony_counter/ui/review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<PlateStore> _tempStore() async {
  final dir = await Directory.systemTemp.createTemp('cc_widget');
  addTearDown(() => dir.delete(recursive: true));
  final store = PlateStore(DirectoryStorage(dir));
  await store.load();
  return store;
}

/// Lets real async work (the counting isolate, file I/O) finish, pumping frames.
Future<void> _settleReal(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 150 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
  }
}

void main() {
  testWidgets('home shows empty state and count button', (tester) async {
    final store = await tester.runAsync(_tempStore);
    await tester.pumpWidget(ColonyCounterApp(store: store!));
    expect(find.text('No plates yet'), findsOneWidget);
    expect(find.text('Count plate'), findsOneWidget);
  });

  testWidgets('review counts a photo, edits by tapping, and saves', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final store = (await tester.runAsync(_tempStore))!;
    final label = jsonDecode(
      File('test/fixtures/sparse.json').readAsStringSync(),
    );
    // Use the colony farthest from any other, so a tap cannot hit a neighbour.
    final points = [for (final p in label['points'] as List) p as List];
    double nearest(List p) => points
        .where((q) => !identical(q, p))
        .map(
          (q) => Offset(
            ((q[0] as num) - (p[0] as num)).toDouble(),
            ((q[1] as num) - (p[1] as num)).toDouble(),
          ).distance,
        )
        .reduce((a, b) => a < b ? a : b);
    final firstColony = points.reduce(
      (a, b) => nearest(a) >= nearest(b) ? a : b,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ReviewScreen(
          store: store,
          photo: File('test/fixtures/sparse.jpg').readAsBytesSync(),
          guided: true,
        ),
      ),
    );
    expect(find.text('Counting colonies…'), findsOneWidget);
    await _settleReal(
      tester,
      () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );
    expect(find.text('automatic'), findsOneWidget);

    final auto = int.parse(
      (tester.widget<Text>(find.textContaining(RegExp(r'^\d+$')).first)).data!,
    );
    expect((auto - (label['true_count'] as int)).abs(), lessThanOrEqualTo(3));

    // Map image pixels to screen: the photo is drawn into a box of its own pixel size.
    final imageBox = find.byType(Image);
    final rect = tester.getRect(imageBox);
    Offset toScreen(num x, num y) =>
        rect.topLeft + Offset(x.toDouble(), y.toDouble()) * (rect.width / 1000);

    // Tapping a detected colony removes it...
    await tester.tapAt(toScreen(firstColony[0] as num, firstColony[1] as num));
    await tester.pump();
    expect(find.text('${auto - 1}'), findsOneWidget);
    expect(find.textContaining('−1 removed'), findsOneWidget);

    // ...tapping the same empty spot adds a manual mark back.
    await tester.tapAt(toScreen(firstColony[0] as num, firstColony[1] as num));
    await tester.pump();
    expect(find.text('$auto'), findsOneWidget);
    expect(find.textContaining('+1 added'), findsOneWidget);

    // Undo restores the previous state.
    await tester.tap(find.byTooltip('Undo'));
    await tester.pump();
    expect(find.text('${auto - 1}'), findsOneWidget);

    // Save with sample details.
    await tester.tap(find.text('Save plate'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Sample ID'),
      'Lake-A',
    );
    await tester.pump();
    final save = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await _settleReal(tester, () => store.records.isNotEmpty);

    expect(store.records.single.sampleId, 'Lake-A');
    expect(store.records.single.count, auto - 1);
    expect(store.records.single.autoCount, auto);
    expect(store.records.single.guided, isTrue);
    final saved = await tester.runAsync(
      () => store.readPhoto(store.records.single),
    );
    expect(saved, isNotNull);
  });
}
