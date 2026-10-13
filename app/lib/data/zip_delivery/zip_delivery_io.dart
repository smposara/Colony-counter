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
  } finally {
    try {
      await sink.close();
    } finally {
      await dir.delete(recursive: true);
    }
  }
}
