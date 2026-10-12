import 'package:colony_counter/ui/review_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final size in [const Size(360, 800), const Size(1280, 800)]) {
    testWidgets('review at ${size.width} keeps image and controls usable', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ReviewLayout(
              image: ColoredBox(key: ValueKey('photo'), color: Colors.black),
              panel: SizedBox(
                key: ValueKey('controls'),
                height: 250,
                child: Text('Save plate'),
              ),
            ),
          ),
        ),
      );
      final image = tester.getRect(find.byKey(const ValueKey('photo')));
      final panel = tester.getRect(find.byKey(const ValueKey('controls')));
      if (size.width >= 900) {
        expect(panel.left, greaterThanOrEqualTo(image.right));
        expect(image.height, greaterThan(500));
      } else {
        expect(panel.top, greaterThanOrEqualTo(image.bottom));
        expect(image.height, greaterThan(300));
      }
      expect(tester.takeException(), isNull);
    });
  }
}
