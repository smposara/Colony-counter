import 'dart:typed_data';

import 'package:idb_shim/idb_browser.dart';

import 'storage.dart';

const _dbName = 'colony_counter';
const _textStore = 'docs';
const _photoStore = 'photos';

Future<StorageBackend> openDefaultStorage() async {
  final factory = getIdbFactory();
  if (factory == null) return MemoryStorage();
  final db = await factory.open(
    _dbName,
    version: 1,
    onUpgradeNeeded: (e) {
      final db = e.database;
      for (final name in [_textStore, _photoStore]) {
        if (!db.objectStoreNames.contains(name)) db.createObjectStore(name);
      }
    },
  );
  return IndexedDbStorage(db);
}

/// The browser's IndexedDB: survives reloads, holds large photos.
class IndexedDbStorage implements StorageBackend {
  IndexedDbStorage(this.db);

  final Database db;

  Future<Object?> _get(String store, String key) async {
    final txn = db.transaction(store, idbModeReadOnly);
    final value = await txn.objectStore(store).getObject(key);
    await txn.completed;
    return value;
  }

  Future<void> _put(String store, String key, Object value) async {
    final txn = db.transaction(store, idbModeReadWrite);
    await txn.objectStore(store).put(value, key);
    await txn.completed;
  }

  @override
  Future<String?> readText(String key) async =>
      await _get(_textStore, key) as String?;

  @override
  Future<void> writeText(String key, String value) =>
      _put(_textStore, key, value);

  @override
  Future<Uint8List?> readPhoto(String name) async {
    final v = await _get(_photoStore, name);
    if (v == null) return null;
    if (v is Uint8List) return v;
    if (v is ByteBuffer) return v.asUint8List();
    return Uint8List.fromList((v as List).cast<int>());
  }

  @override
  Future<void> writePhoto(String name, Uint8List bytes) =>
      _put(_photoStore, name, bytes);

  @override
  Future<void> deletePhoto(String name) async {
    final txn = db.transaction(_photoStore, idbModeReadWrite);
    await txn.objectStore(_photoStore).delete(name);
    await txn.completed;
  }
}
