import 'package:colony_counter/core/classical.dart';
import 'package:colony_counter/core/plate.dart';
import 'package:colony_counter/data/plate_record.dart';
import 'package:colony_counter/data/plate_store.dart';
import 'package:colony_counter/data/storage/storage.dart';
import 'package:colony_counter/ui/save_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Save keeps notes and hours typed just before it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final store = PlateStore(MemoryStorage());
    await tester.runAsync(store.load);
    final draft = PlateRecord(
      id: 'p1',
      createdAt: DateTime(2026, 10, 4),
      imagePath: 'x.jpg',
      imageWidth: 1000,
      imageHeight: 1000,
      plate: const Plate(500, 500, 450),
      colonies: const [Colony(500, 500, 5)],
      autoCount: 1,
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
    // No rebuild between typing and Save (the keyboard stays open).
    tester
            .widget<TextField>(find.widgetWithText(TextField, 'Notes'))
            .controller!
            .text =
        'smeared';
    tester
            .widget<TextField>(
              find.widgetWithText(TextField, 'Incubation time (optional)'),
            )
            .controller!
            .text =
        '48';
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(saved?.notes, 'smeared');
    expect(saved?.incubationH, 48);
  });
}
