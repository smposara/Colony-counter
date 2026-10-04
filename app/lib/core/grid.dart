import 'dart:math' as math;
import 'dart:typed_data';

import 'gray_image.dart';

/// Removes the printed grid of a membrane filter from the contrast map [fg]
/// (colonies positive), keeping the colonies.
///
/// Grid lines are long and thin, colonies are compact. A grayscale opening
/// with a line [lengthMm] long keeps only structures that contain such a line,
/// i.e. the grid; it is taken over 18 directions and subtracted. The opening
/// runs on a max-pooled copy at about [workPxPerMm] so thin lines survive the
/// downscale, then is applied back at full resolution.
GrayImage suppressGridLines(
  GrayImage fg,
  Uint8List mask,
  double mmPerPx, {
  double lengthMm = 4,
  double workPxPerMm = 6,
}) {
  final w = fg.width, h = fg.height;
  var x0 = w, y0 = h, x1 = -1, y1 = -1;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (mask[y * w + x] == 0) continue;
      if (x < x0) x0 = x;
      if (x > x1) x1 = x;
      if (y < y0) y0 = y;
      if (y > y1) y1 = y;
    }
  }
  final out = fg.copy();
  if (x1 < 0) return out;

  final f = math.max(1, (1 / (workPxPerMm * mmPerPx)).ceil());
  final sw = (x1 - x0) ~/ f + 1, sh = (y1 - y0) ~/ f + 1;
  // Max-pool, then a 3 × 3 max so lines are at least ~3 px wide.
  final pooled = Float32List(sw * sh);
  for (var y = y0; y <= y1; y++) {
    for (var x = x0; x <= x1; x++) {
      final i = y * w + x;
      if (mask[i] == 0) continue;
      final j = ((y - y0) ~/ f) * sw + (x - x0) ~/ f;
      if (fg.data[i] > pooled[j]) pooled[j] = fg.data[i];
    }
  }
  final small = Float32List(sw * sh);
  for (var y = 0; y < sh; y++) {
    for (var x = 0; x < sw; x++) {
      var m = 0.0;
      for (var dy = -1; dy <= 1; dy++) {
        final yy = y + dy;
        if (yy < 0 || yy >= sh) continue;
        for (var dx = -1; dx <= 1; dx++) {
          final xx = x + dx;
          if (xx >= 0 && xx < sw) m = math.max(m, pooled[yy * sw + xx]);
        }
      }
      small[y * sw + x] = m;
    }
  }

  final half = math.max(2, (lengthMm / (mmPerPx * f) / 2).round());
  final lines = Float32List(sw * sh);
  final eroded = Float32List(sw * sh);
  for (var k = 0; k < 18; k++) {
    final a = math.pi * k / 18;
    final offsets = <(int, int)>{
      for (var t = -half; t <= half; t++)
        ((t * math.cos(a)).round(), (t * math.sin(a)).round()),
    }.toList();
    for (var y = 0; y < sh; y++) {
      for (var x = 0; x < sw; x++) {
        var m = double.infinity;
        for (final (dx, dy) in offsets) {
          final xx = x + dx, yy = y + dy;
          final v = (xx < 0 || yy < 0 || xx >= sw || yy >= sh)
              ? 0.0
              : small[yy * sw + xx];
          if (v < m) {
            m = v;
            if (m <= 0) break;
          }
        }
        eroded[y * sw + x] = m;
      }
    }
    for (var y = 0; y < sh; y++) {
      for (var x = 0; x < sw; x++) {
        var m = 0.0;
        for (final (dx, dy) in offsets) {
          final xx = x + dx, yy = y + dy;
          if (xx < 0 || yy < 0 || xx >= sw || yy >= sh) continue;
          final v = eroded[yy * sw + xx];
          if (v > m) m = v;
        }
        final i = y * sw + x;
        if (m > lines[i]) lines[i] = m;
      }
    }
  }

  for (var y = y0; y <= y1; y++) {
    for (var x = x0; x <= x1; x++) {
      final i = y * w + x;
      if (mask[i] == 0) continue;
      out.data[i] = fg.data[i] - lines[((y - y0) ~/ f) * sw + (x - x0) ~/ f];
    }
  }
  return out;
}
