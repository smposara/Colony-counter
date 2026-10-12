import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'storage.dart';
import 'serial_queue.dart';

Future<StorageBackend> openDefaultStorage() async {
  final docs = await getApplicationDocumentsDirectory();
  return DirectoryStorage(Directory('${docs.path}/colony_counter'));
}

/// JSON documents as `<root>/<key>.json`, photos in `<root>/photos/`.
class DirectoryStorage implements StorageBackend {
  DirectoryStorage(this.root);

  final Directory root;
  final _writes = SerialQueue();
  int _sequence = 0;

  Directory get photoDir => Directory('${root.path}/photos');

  @override
  Future<String?> readText(String key) async {
    final f = File('${root.path}/$key.json');
    return await f.exists() ? f.readAsString() : null;
  }

  Future<void> _atomicWrite(
    File target,
    List<int> bytes,
  ) => _writes.run(() async {
    await target.parent.create(recursive: true);
    final tmp = File(
      '${target.path}.${DateTime.now().microsecondsSinceEpoch}_${_sequence++}.tmp',
    );
    try {
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(target.path);
    } finally {
      if (await tmp.exists()) await tmp.delete();
    }
  });

  @override
  Future<void> writeText(String key, String value) =>
      _atomicWrite(File('${root.path}/$key.json'), utf8.encode(value));

  @override
  Future<Uint8List?> readPhoto(String name) async {
    final f = File('${photoDir.path}/$name');
    return await f.exists() ? f.readAsBytes() : null;
  }

  @override
  Future<void> writePhoto(String name, Uint8List bytes) =>
      _atomicWrite(File('${photoDir.path}/$name'), bytes);

  @override
  Future<void> deletePhoto(String name) async {
    final f = File('${photoDir.path}/$name');
    if (await f.exists()) await f.delete();
  }
}
