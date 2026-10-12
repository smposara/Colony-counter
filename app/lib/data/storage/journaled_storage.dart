import 'dart:convert';
import 'dart:typed_data';

import 'serial_queue.dart';
import 'storage.dart';

/// One durable journal is the commit point for a group of JSON documents.
/// An interrupted materialisation is replayed before the next read or write.
/// Photos are written before committing records and cleaned up afterwards.
class JournaledStorage implements StorageBackend {
  JournaledStorage(this.delegate);

  final StorageBackend delegate;
  final SerialQueue _queue = SerialQueue();
  static const journalKey = 'pending_transaction';
  Map<String, String>? _pending;

  Future<void> _readJournal() async {
    if (_pending != null) return;
    final text = await delegate.readText(journalKey);
    _pending = text == null
        ? <String, String>{}
        : (jsonDecode(text) as Map<String, dynamic>).cast<String, String>();
  }

  Future<void> _flush() async {
    await _readJournal();
    if (_pending!.isEmpty) return;
    for (final entry in _pending!.entries) {
      await delegate.writeText(entry.key, entry.value);
    }
    await delegate.writeText(journalKey, '{}');
    _pending = {};
  }

  Future<void> writeDocuments(Map<String, String> documents) => _queue.run(
    () async {
      await _flush();
      // A successful atomic journal write makes every document recoverable.
      await delegate.writeText(journalKey, jsonEncode(documents));
      _pending = Map.of(documents);
      try {
        await _flush();
      } catch (_) {
        // Committed data remains authoritative in the journal. Retry later;
        // reporting a failed save here would invite duplicate records on retry.
      }
    },
  );

  @override
  Future<String?> readText(String key) => _queue.run(() async {
    await _readJournal();
    if (_pending!.containsKey(key)) return _pending![key];
    return delegate.readText(key);
  });

  @override
  Future<void> writeText(String key, String value) =>
      writeDocuments({key: value});

  @override
  Future<Uint8List?> readPhoto(String name) => delegate.readPhoto(name);
  @override
  Future<void> writePhoto(String name, Uint8List bytes) =>
      delegate.writePhoto(name, bytes);
  @override
  Future<void> deletePhoto(String name) => delegate.deletePhoto(name);
}
