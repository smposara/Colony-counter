import 'dart:io';

import 'package:colony_counter/core/pipeline.dart';
import 'package:colony_counter/data/plate_record.dart';
import 'package:colony_counter/data/plate_store.dart';
import 'package:colony_counter/data/storage/storage.dart';
import 'package:colony_counter/ui/review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('recounting a verified saved plate requires a new confirmation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final bytes = File('test/fixtures/sparse.jpg').readAsBytesSync();
    final result = countPhoto(bytes);
    final store = PlateStore(MemoryStorage());
    final path = await store.savePhoto(bytes, 'verified');
    final record = PlateRecord(
      id: 'verified',
      createdAt: DateTime(2026),
      imagePath: path,
      imageWidth: result.imageWidth,
      imageHeight: result.imageHeight,
      plate: result.plate,
      colonies: result.colonies,
      autoCount: result.count,
      verified: true,
    );
    await store.upsert(record);
    await tester.pumpWidget(
      MaterialApp(
        home: ReviewScreen(store: store, record: record),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Detection sensitivity'));
    await tester.pumpAndSettle();
    tester.widget<Slider>(find.byType(Slider)).onChanged!(7.5);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Recount'));
    await tester.pump();
    for (
      var i = 0;
      i < 150 && find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    final verification = find.widgetWithText(
      SwitchListTile,
      'Checked every colony',
    );
    expect(tester.widget<SwitchListTile>(verification).value, isFalse);
    final save = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(store.records.single.verified, isFalse);
  });
}
