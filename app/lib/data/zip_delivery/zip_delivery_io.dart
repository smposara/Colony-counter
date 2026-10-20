import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Export folders still being written or shared: never cleaned up.
final _inUse = <String>{};

/// How long a shared export is kept for the receiving app to read it.
const _keepShared = Duration(hours: 1);

Future<void> deliverZip(
  Stream<Uint8List> chunks,
  String name,
  String subject,
) async {
  final temp = await getTemporaryDirectory();
  final parent = await Directory('${temp.path}/colony-backup')
      .create(recursive: true);
  final dir = await parent.createTemp();
  _inUse.add(dir.path);
  // The receiving app may read the file after share() returns (Android hands
  // over a content URI), so earlier exports are removed later, once they are
  // an hour old, and never while another export still writes or shares one.
  final now = DateTime.now();
  await for (final old in parent.list()) {
    if (_inUse.contains(old.path)) continue;
    try {
      if (now.difference((await old.stat()).modified) < _keepShared) continue;
      await old.delete(recursive: true);
    } catch (_) {
      /* still in use; removed next time */
    }
  }
  final file = File('${dir.path}/$name');
  final sink = file.openWrite();
  try {
    await sink.addStream(chunks);
    await sink.flush();
    await sink.close();
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/zip')],
        subject: subject,
      ),
    );
  } catch (_) {
    await sink.close().catchError((_) {});
    await dir.delete(recursive: true).catchError((_) => dir);
    rethrow;
  } finally {
    _inUse.remove(dir.path);
  }
}
