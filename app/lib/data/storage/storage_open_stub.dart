import 'storage.dart';

Future<StorageBackend> openDefaultStorage() async => MemoryStorage();
