import 'package:colony_counter/data/examples.dart';
import 'package:colony_counter/data/plate_store.dart';
import 'package:colony_counter/data/storage/storage.dart';
import 'package:colony_counter/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the time-kill chart fits on a tablet screen', (tester) async {
    tester.view.physicalSize = const Size(2560, 1600); // 1280 × 800
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final store = PlateStore(MemoryStorage());
    await tester.runAsync(() async {
      await store.load();
      await store.setDefaults(language: 'en');
      await addExamples(store);
    });
    await tester.pumpWidget(ColonyCounterApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compare').first);
    await tester.pumpAndSettle();
    final chart = find.byWidgetPredicate(
      (w) =>
          w is CustomPaint &&
          w.painter.runtimeType.toString() == '_ChartPainter',
    );
    expect(chart, findsOneWidget);
    final r = tester.getRect(chart);
    expect(r.height, lessThanOrEqualTo(380));
    expect(r.bottom, lessThanOrEqualTo(800));
  });
}
