import 'dart:typed_data';

export 'storage_open_stub.dart'
    if (dart.library.io) 'storage_io.dart'
    if (dart.library.js_interop) 'storage_web.dart'
    show openDefaultStorage;

/// Where the app keeps its JSON documents and plate photos.
///
/// Phones use files in the app's documents folder ([DirectoryStorage]);
/// the web version uses the browser's IndexedDB ([IndexedDbStorage]).
abstract class StorageBackend {
  Future<String?> readText(String key);
  Future<void> writeText(String key, String value);
  Future<Uint8List?> readPhoto(String name);
  Future<void> writePhoto(String name, Uint8List bytes);
  Future<void> deletePhoto(String name);
}

/// Keeps everything in memory; used by tests and as a last resort.
class MemoryStorage implements StorageBackend {
  final _text = <String, String>{};
  final _photos = <String, Uint8List>{};

  @override
  Future<String?> readText(String key) async => _text[key];

  @override
  Future<void> writeText(String key, String value) async => _text[key] = value;

  @override
  Future<Uint8List?> readPhoto(String name) async => _photos[name];

  @override
  Future<void> writePhoto(String name, Uint8List bytes) async =>
      _photos[name] = bytes;

  @override
  Future<void> deletePhoto(String name) async => _photos.remove(name);
}
