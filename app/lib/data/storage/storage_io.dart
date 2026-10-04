import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'storage.dart';

Future<StorageBackend> openDefaultStorage() async {
  final docs = await getApplicationDocumentsDirectory();
  return DirectoryStorage(Directory('${docs.path}/colony_counter'));
}

/// JSON documents as `<root>/<key>.json`, photos in `<root>/photos/`.
class DirectoryStorage implements StorageBackend {
  DirectoryStorage(this.root);

  final Directory root;

  Directory get photoDir => Directory('${root.path}/photos');

  @override
  Future<String?> readText(String key) async {
    final f = File('${root.path}/$key.json');
    return await f.exists() ? f.readAsString() : null;
  }

  @override
  Future<void> writeText(String key, String value) async {
    await root.create(recursive: true);
    // Write then rename, so a crash never leaves a half-written file.
    final tmp = File('${root.path}/$key.json.tmp');
    await tmp.writeAsString(value, flush: true);
    await tmp.rename('${root.path}/$key.json');
  }

  @override
  Future<Uint8List?> readPhoto(String name) async {
    final f = File('${photoDir.path}/$name');
    return await f.exists() ? f.readAsBytes() : null;
  }

  @override
  Future<void> writePhoto(String name, Uint8List bytes) async {
    await photoDir.create(recursive: true);
    await File('${photoDir.path}/$name').writeAsBytes(bytes, flush: true);
  }

  @override
  Future<void> deletePhoto(String name) async {
    final f = File('${photoDir.path}/$name');
    if (await f.exists()) await f.delete();
  }
}
