import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

const kWorkShortSide = 1800;
const kMaxWorkSide = 3000;
const kMaxWorkPixels = 4500000;
// 48/50 MP phone sensors deliver full-size photos with ResolutionPreset.max.
const kMaxDecodedPixels = 52000000;
const kMaxEncodedBytes = 40 * 1024 * 1024;

/// Inspect dimensions before allocating full decoded pixel buffers.
img.Image decodePlatePhoto(Uint8List bytes) {
  if (bytes.lengthInBytes > kMaxEncodedBytes) {
    throw const FormatException('Photo is too large. Choose a smaller photo.');
  }
  final decoder = img.findDecoderForData(bytes);
  final info = decoder?.startDecode(bytes);
  if (info == null || info.width <= 0 || info.height <= 0) {
    throw const FormatException('Unsupported image');
  }
  if (info.width * info.height > kMaxDecodedPixels) {
    throw const FormatException(
      'Photo exceeds 50 megapixels. Choose a smaller photo.',
    );
  }
  final decoded = decoder!.decodeFrame(0);
  if (decoded == null) throw const FormatException('Unsupported image');
  return img.bakeOrientation(decoded);
}

/// Bound both dimensions and total work, including panoramic photos.
double analysisScale(int width, int height) => math.min(
  1.0,
  math.min(
    kWorkShortSide / math.min(width, height),
    math.min(
      kMaxWorkSide / math.max(width, height),
      math.sqrt(kMaxWorkPixels / (width * height)),
    ),
  ),
);
