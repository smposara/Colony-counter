import 'dart:math' as math;
import 'dart:typed_data';

/// Live image-quality measures for the capture guide, computed on the camera's
/// luminance plane inside the centred guide circle.
class FrameQuality {
  const FrameQuality({required this.sharpness, required this.glareFraction});

  /// Variance of the Laplacian: higher is sharper. Only meaningful relative to
  /// other frames from the same phone and scene.
  final double sharpness;

  /// Fraction of guide-circle pixels that are clipped (≥ 250).
  final double glareFraction;
}

/// [luma] is an 8-bit luminance plane; [rowStride] bytes per row and
/// [pixelStride] bytes between neighbouring pixels (4 for BGRA, using the G byte
/// at [offset] 1). [guideFraction] is the guide circle diameter relative to the
/// shorter side. Samples every [step]-th pixel for speed.
FrameQuality measureFrame(
  Uint8List luma, {
  required int width,
  required int height,
  required int rowStride,
  int pixelStride = 1,
  int offset = 0,
  double guideFraction = 0.8,
  int step = 3,
}) {
  final cx = width / 2, cy = height / 2;
  final r = math.min(width, height) * guideFraction / 2;
  final r2 = r * r;
  int px(int x, int y) => luma[y * rowStride + x * pixelStride + offset];

  var n = 0, clipped = 0;
  var sum = 0.0, sumSq = 0.0;
  for (var y = step; y < height - step; y += step) {
    final dy = y - cy;
    for (var x = step; x < width - step; x += step) {
      final dx = x - cx;
      if (dx * dx + dy * dy > r2) continue;
      final c = px(x, y);
      if (c >= 250) clipped++;
      final lap =
          (px(x - 1, y) + px(x + 1, y) + px(x, y - 1) + px(x, y + 1) - 4 * c)
              .toDouble();
      sum += lap;
      sumSq += lap * lap;
      n++;
    }
  }
  if (n == 0) return const FrameQuality(sharpness: 0, glareFraction: 0);
  final mean = sum / n;
  return FrameQuality(
    sharpness: sumSq / n - mean * mean,
    glareFraction: clipped / n,
  );
}

/// Angle between the phone's screen normal and vertical, from an accelerometer
/// reading (m/s²). 0° means lying flat, camera facing straight down.
double tiltDegrees(double x, double y, double z) {
  final g = math.sqrt(x * x + y * y + z * z);
  if (g == 0) return 90;
  return math.acos((z.abs() / g).clamp(0.0, 1.0)) * 180 / math.pi;
}

/// Tracks recent sharpness so "sharp" means close to the best focus seen lately,
/// which works across phones whose absolute values differ.
class SharpnessTracker {
  SharpnessTracker({this.window = 20, this.ratio = 0.6});

  final int window;
  final double ratio;
  final List<double> _recent = [];

  bool add(double value) {
    _recent.add(value);
    if (_recent.length > window) _recent.removeAt(0);
    final best = _recent.reduce(math.max);
    return best > 5 && value >= ratio * best;
  }
}
