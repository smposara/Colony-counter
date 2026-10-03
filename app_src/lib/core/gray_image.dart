import 'dart:math' as math;
import 'dart:typed_data';

/// A single-channel float image stored row by row.
class GrayImage {
  GrayImage(this.width, this.height, [Float32List? data])
      : data = data ?? Float32List(width * height) {
    assert(this.data.length == width * height);
  }

  final int width;
  final int height;
  final Float32List data;

  double at(int x, int y) => data[y * width + x];

  GrayImage copy() => GrayImage(width, height, Float32List.fromList(data));

  /// Area-average downscale or bilinear upscale to [w] x [h].
  GrayImage resize(int w, int h) {
    if (w == width && h == height) return copy();
    return (w < width && h < height) ? _shrink(w, h) : _bilinear(w, h);
  }

  GrayImage _shrink(int w, int h) {
    final out = GrayImage(w, h);
    final sx = width / w, sy = height / h;
    for (var y = 0; y < h; y++) {
      final y0 = (y * sy).floor(), y1 = math.max(y0 + 1, ((y + 1) * sy).floor());
      for (var x = 0; x < w; x++) {
        final x0 = (x * sx).floor(), x1 = math.max(x0 + 1, ((x + 1) * sx).floor());
        var sum = 0.0;
        var n = 0;
        for (var yy = y0; yy < y1 && yy < height; yy++) {
          final row = yy * width;
          for (var xx = x0; xx < x1 && xx < width; xx++) {
            sum += data[row + xx];
            n++;
          }
        }
        out.data[y * w + x] = n > 0 ? sum / n : 0;
      }
    }
    return out;
  }

  GrayImage _bilinear(int w, int h) {
    final out = GrayImage(w, h);
    final sx = width / w, sy = height / h;
    for (var y = 0; y < h; y++) {
      final fy = ((y + 0.5) * sy - 0.5).clamp(0.0, height - 1.0);
      final y0 = fy.floor(), y1 = math.min(y0 + 1, height - 1);
      final ty = fy - y0;
      for (var x = 0; x < w; x++) {
        final fx = ((x + 0.5) * sx - 0.5).clamp(0.0, width - 1.0);
        final x0 = fx.floor(), x1 = math.min(x0 + 1, width - 1);
        final tx = fx - x0;
        final a = data[y0 * width + x0], b = data[y0 * width + x1];
        final c = data[y1 * width + x0], d = data[y1 * width + x1];
        out.data[y * w + x] =
            (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty;
      }
    }
    return out;
  }

  /// Separable Gaussian blur.
  GrayImage gaussianBlur(double sigma) {
    final r = math.max(1, (sigma * 3).ceil());
    final k = Float32List(2 * r + 1);
    var s = 0.0;
    for (var i = -r; i <= r; i++) {
      k[i + r] = math.exp(-(i * i) / (2 * sigma * sigma));
      s += k[i + r];
    }
    for (var i = 0; i < k.length; i++) {
      k[i] /= s;
    }
    final tmp = GrayImage(width, height);
    final out = GrayImage(width, height);
    for (var y = 0; y < height; y++) {
      final row = y * width;
      for (var x = 0; x < width; x++) {
        var acc = 0.0;
        for (var i = -r; i <= r; i++) {
          final xx = (x + i).clamp(0, width - 1);
          acc += data[row + xx] * k[i + r];
        }
        tmp.data[row + x] = acc;
      }
    }
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        var acc = 0.0;
        for (var i = -r; i <= r; i++) {
          final yy = (y + i).clamp(0, height - 1);
          acc += tmp.data[yy * width + x] * k[i + r];
        }
        out.data[y * width + x] = acc;
      }
    }
    return out;
  }

  /// Median filter with a square [k] x [k] window (k odd), using a sliding
  /// histogram over values quantised to 256 levels between min and max.
  GrayImage medianFilter(int k) {
    var lo = double.infinity, hi = -double.infinity;
    for (final v in data) {
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    final span = math.max(hi - lo, 1e-6);
    final q = Uint8List(data.length);
    for (var i = 0; i < data.length; i++) {
      q[i] = ((data[i] - lo) / span * 255).round().clamp(0, 255);
    }
    final r = k ~/ 2;
    final out = GrayImage(width, height);
    final hist = Int32List(256);
    // Edge pixels are replicated (border clamp).
    int px(int x, int y) => q[y.clamp(0, height - 1) * width + x.clamp(0, width - 1)];
    final half = (k * k) ~/ 2;
    for (var y = 0; y < height; y++) {
      hist.fillRange(0, 256, 0);
      for (var dy = -r; dy <= r; dy++) {
        for (var dx = -r; dx <= r; dx++) {
          hist[px(dx, y + dy)]++;
        }
      }
      for (var x = 0; x < width; x++) {
        if (x > 0) {
          for (var dy = -r; dy <= r; dy++) {
            hist[px(x - r - 1, y + dy)]--;
            hist[px(x + r, y + dy)]++;
          }
        }
        var acc = 0, m = 0;
        while (true) {
          acc += hist[m];
          if (acc > half) break;
          m++;
        }
        out.data[y * width + x] = m / 255 * span + lo;
      }
    }
    return out;
  }
}

/// Median of a sample of values (the list is sorted in place).
double median(List<double> v) {
  if (v.isEmpty) return 0;
  v.sort();
  final n = v.length;
  return n.isOdd ? v[n ~/ 2] : (v[n ~/ 2 - 1] + v[n ~/ 2]) / 2;
}

/// The [p]-th percentile (0-100) of an already sorted list.
double percentileSorted(List<double> sorted, double p) {
  if (sorted.isEmpty) return 0;
  final idx = (p / 100 * (sorted.length - 1)).clamp(0, sorted.length - 1);
  final i0 = idx.floor(), i1 = math.min(i0 + 1, sorted.length - 1);
  final t = idx - i0;
  return sorted[i0] * (1 - t) + sorted[i1] * t;
}
