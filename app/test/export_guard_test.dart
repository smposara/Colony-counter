import 'package:colony_counter/core/classical.dart';
import 'package:colony_counter/core/plate.dart';
import 'package:colony_counter/data/plate_record.dart';
import 'package:colony_counter/data/plate_store.dart';
import 'package:colony_counter/data/storage/storage.dart';
import 'package:colony_counter/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a training-data choice left open does not block later '
      'exports', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final store = PlateStore(MemoryStorage());
    await tester.runAsync(() async {
      await store.load();
      await store.setDefaults(language: 'en');
      await store.upsert(
        PlateRecord(
          id: 'p1',
          createdAt: DateTime(2026, 10, 4),
          imagePath: 'p1.jpg',
          imageWidth: 1000,
          imageHeight: 1000,
          plate: const Plate(500, 500, 450),
          colonies: const [Colony(500, 500, 5)],
          autoCount: 1,
        ),
      );
    });
    for (var i = 0; i < 2; i++) {
      // A new home screen each time; the first one goes away with its
      // choice still open (the app was closed or rebuilt).
      await tester.pumpWidget(ColonyCounterApp(key: UniqueKey(), store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.more_vert).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export training data'));
      await tester.pumpAndSettle();
      expect(find.byType(SimpleDialog), findsOneWidget, reason: 'try $i');
      expect(find.text('This export is still in progress.'), findsNothing);
    }
  });
}
