import 'dart:convert';

import 'package:colony_counter/data/storage/journaled_storage.dart';
import 'package:colony_counter/data/storage/serial_queue.dart';
import 'package:colony_counter/data/storage/storage.dart';
import 'package:flutter_test/flutter_test.dart';

class FaultStorage extends MemoryStorage {
  String? failKey;
  @override
  Future<void> writeText(String key, String value) async {
    if (key == failKey) throw StateError('write failed');
    return super.writeText(key, value);
  }
}

void main() {
  test('failed journal commit leaves existing documents unchanged', () async {
    final backend = FaultStorage();
    await backend.writeText('a', 'old');
    backend.failKey = JournaledStorage.journalKey;
    final storage = JournaledStorage(backend);
    await expectLater(
      storage.writeDocuments({'a': 'new', 'b': 'new'}),
      throwsStateError,
    );
    expect(await storage.readText('a'), 'old');
    expect(await storage.readText('b'), isNull);
  });

  test(
    'interrupted materialisation recovers all documents on restart',
    () async {
      final backend = FaultStorage()..failKey = 'b';
      final storage = JournaledStorage(backend);
      await storage.writeDocuments({'a': 'new-a', 'b': 'new-b'});
      final restarted = JournaledStorage(backend);
      expect(await restarted.readText('a'), 'new-a');
      expect(await restarted.readText('b'), 'new-b');
      backend.failKey = null;
      await restarted.writeDocuments({'c': 'later'});
      expect(await backend.readText('b'), 'new-b');
      expect(
        jsonDecode((await backend.readText(JournaledStorage.journalKey))!),
        isEmpty,
      );
    },
  );

  test(
    'queue continues after a failed operation and preserves order',
    () async {
      final queue = SerialQueue();
      final order = <int>[];
      final failed = queue.run(() async {
        order.add(1);
        throw StateError('failure');
      });
      final next = queue.run(() async {
        order.add(2);
        return 2;
      });
      await expectLater(failed, throwsStateError);
      expect(await next, 2);
      expect(order, [1, 2]);
    },
  );
}
