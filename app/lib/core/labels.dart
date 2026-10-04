import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

/// What a plate label identifies: a sample and, optionally, the plate's
/// dilution and replicate within it.
class PlateLabel {
  const PlateLabel(this.sampleId, {this.dilutionExp, this.replicate});

  final String sampleId;
  final int? dilutionExp;
  final int? replicate;

  /// Compact QR payload, e.g. `CC1;s=Lake-A;d=4;r=2`. The sample ID is
  /// percent-encoded so it can contain any character.
  String encode() => [
    'CC1',
    's=${Uri.encodeComponent(sampleId)}',
    if (dilutionExp != null) 'd=$dilutionExp',
    if (replicate != null) 'r=$replicate',
  ].join(';');

  /// Parses a payload made by [encode]; null for anything else.
  static PlateLabel? parse(String text) {
    final parts = text.trim().split(';');
    if (parts.isEmpty || parts.first != 'CC1') return null;
    final fields = <String, String>{
      for (final p in parts.skip(1))
        if (p.contains('='))
          p.substring(0, p.indexOf('=')): p.substring(p.indexOf('=') + 1),
    };
    final s = fields['s'];
    if (s == null || s.isEmpty) return null;
    return PlateLabel(
      Uri.decodeComponent(s),
      dilutionExp: int.tryParse(fields['d'] ?? ''),
      replicate: int.tryParse(fields['r'] ?? ''),
    );
  }

  /// Human-readable line printed under the code: "Lake-A · 10^-4 · R2".
  String get caption => [
    sampleId,
    if (dilutionExp != null) '10^-$dilutionExp',
    if (replicate != null) 'R$replicate',
  ].join(' · ');
}

/// Finds and reads a plate label QR code in a photo (JPEG/PNG bytes).
///
/// Tries a few sizes and binarisers, because phone photos of labels vary in
/// scale, focus and lighting. Returns null when no Colony Counter label is found.
PlateLabel? readLabelFromPhoto(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final photo = img.bakeOrientation(decoded);
  for (final side in const [1000, 1600, 600]) {
    final scale = math.min(1.0, side / math.max(photo.width, photo.height));
    final im = scale < 1
        ? img.copyResize(
            photo,
            width: (photo.width * scale).round(),
            interpolation: img.Interpolation.average,
          )
        : photo;
    final text = _decodeQr(im);
    final label = text == null ? null : PlateLabel.parse(text);
    if (label != null) return label;
  }
  return null;
}

String? _decodeQr(img.Image im) {
  final pixels = im
      .convert(numChannels: 4)
      .getBytes(order: img.ChannelOrder.abgr)
      .buffer
      .asInt32List();
  final source = RGBLuminanceSource(im.width, im.height, pixels);
  final hints = DecodeHints()..put(DecodeHintType.tryHarder);
  for (final binarizer in [
    HybridBinarizer(source),
    GlobalHistogramBinarizer(source),
  ]) {
    try {
      return QRCodeReader().decode(BinaryBitmap(binarizer), hints: hints).text;
    } on ReaderException {
      // Try the next binariser / size.
    }
  }
  return null;
}

/// Renders [label] as a QR image (black on white, [moduleSize] px per module
/// plus a 4-module quiet zone). Used by tests and for on-screen preview.
img.Image renderLabelQr(PlateLabel label, {int moduleSize = 8}) {
  final qr = Encoder.encode(label.encode(), ErrorCorrectionLevel.m).matrix!;
  const quiet = 4;
  final size = (qr.width + 2 * quiet) * moduleSize;
  final out = img.Image(width: size, height: size)
    ..clear(img.ColorRgb8(255, 255, 255));
  for (var y = 0; y < qr.height; y++) {
    for (var x = 0; x < qr.width; x++) {
      if (qr.get(x, y) == 1) {
        img.fillRect(
          out,
          x1: (x + quiet) * moduleSize,
          y1: (y + quiet) * moduleSize,
          x2: (x + quiet + 1) * moduleSize - 1,
          y2: (y + quiet + 1) * moduleSize - 1,
          color: img.ColorRgb8(0, 0, 0),
        );
      }
    }
  }
  return out;
}
