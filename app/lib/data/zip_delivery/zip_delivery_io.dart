import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

Future<void> deliverZip(
  Stream<Uint8List> chunks,
  String name,
  String subject,
) async {
  final temp = await getTemporaryDirectory();
  final parent = await Directory('${temp.path}/colony-backup')
      .create(recursive: true);
  // The receiving app may read the file after share() returns (Android hands
  // over a content URI), so earlier exports are removed now, not this one.
  await for (final old in parent.list()) {
    try {
      await old.delete(recursive: true);
    } catch (_) {
      /* still in use; removed next time */
    }
  }
  final dir = await parent.createTemp();
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
  }
}
