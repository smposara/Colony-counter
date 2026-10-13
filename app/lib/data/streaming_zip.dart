import 'dart:convert';
import 'dart:typed_data';

class ZipEntrySource {
  const ZipEntrySource(this.name, this.read);
  final String name;
  final Future<Uint8List?> Function() read;
}

final _crcTable = List<int>.generate(256, (i) {
  var c = i;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xedb88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});
Uint8List _header(int length, void Function(ByteData) fill) {
  final bytes = Uint8List(length);
  fill(ByteData.sublistView(bytes));
  return bytes;
}

/// Stored ZIP entries with data descriptors: bounded photo/chunk memory and
/// only small central-directory records retained. Standard ZIP (under 4 GiB).
Stream<Uint8List> streamZip(Stream<ZipEntrySource> entries) async* {
  final directory = <Uint8List>[];
  var offset = 0;
  await for (final entry in entries) {
    final bytes = await entry.read();
    if (bytes == null) continue;
    final name = Uint8List.fromList(utf8.encode(entry.name));
    if (name.length > 65535 ||
        directory.length >= 65535 ||
        offset + bytes.length + name.length + 46 > 0xffffffff) {
      throw StateError(
        'Backup exceeds the standard ZIP limit (4 GiB or 65,535 files).',
      );
    }
    final start = offset;
    final local = _header(30, (d) {
      d.setUint32(0, 0x04034b50, Endian.little);
      d.setUint16(4, 20, Endian.little);
      d.setUint16(6, 0x0808, Endian.little);
      d.setUint16(12, 0x0021, Endian.little);
      d.setUint16(26, name.length, Endian.little);
    });
    yield local;
    yield name;
    offset += 30 + name.length;
    var crc = 0xffffffff;
    for (var pos = 0; pos < bytes.length; pos += 65536) {
      final end = (pos + 65536).clamp(0, bytes.length);
      final chunk = Uint8List.sublistView(bytes, pos, end);
      for (final byte in chunk) {
        crc = _crcTable[(crc ^ byte) & 255] ^ (crc >> 8);
      }
      yield chunk;
      offset += chunk.length;
      // Let browser input/progress events run between bounded CRC blocks.
      await Future<void>.delayed(Duration.zero);
    }
    crc = (crc ^ 0xffffffff) & 0xffffffff;
    yield _header(16, (d) {
      d.setUint32(0, 0x08074b50, Endian.little);
      d.setUint32(4, crc, Endian.little);
      d.setUint32(8, bytes.length, Endian.little);
      d.setUint32(12, bytes.length, Endian.little);
    });
    offset += 16;
    final central = _header(46, (d) {
      d.setUint32(0, 0x02014b50, Endian.little);
      d.setUint16(4, 20, Endian.little);
      d.setUint16(6, 20, Endian.little);
      d.setUint16(8, 0x0808, Endian.little);
      d.setUint16(14, 0x0021, Endian.little);
      d.setUint32(16, crc, Endian.little);
      d.setUint32(20, bytes.length, Endian.little);
      d.setUint32(24, bytes.length, Endian.little);
      d.setUint16(28, name.length, Endian.little);
      d.setUint32(42, start, Endian.little);
    });
    directory.add(Uint8List.fromList([...central, ...name]));
  }
  final start = offset;
  for (final record in directory) {
    yield record;
    offset += record.length;
  }
  if (offset + 22 > 0xffffffff) throw StateError('Backup exceeds 4 GiB.');
  yield _header(22, (d) {
    d.setUint32(0, 0x06054b50, Endian.little);
    d.setUint16(8, directory.length, Endian.little);
    d.setUint16(10, directory.length, Endian.little);
    d.setUint32(12, offset - start, Endian.little);
    d.setUint32(16, start, Endian.little);
  });
}
