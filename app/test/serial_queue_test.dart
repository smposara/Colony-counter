import 'package:colony_counter/data/storage/serial_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('idle queue crosses simulated and real clocks without hanging', (
    tester,
  ) async {
    final queue = SerialQueue();
    expect(await tester.runAsync(() => queue.run(() async => 1)), 1);
    expect(await queue.run(() async => 2), 2);
    await expectLater(
      queue.run(() async => throw StateError('failed')),
      throwsStateError,
    );
    expect(await tester.runAsync(() => queue.run(() async => 3)), 3);
  });
}
