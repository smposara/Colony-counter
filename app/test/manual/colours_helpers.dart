// Synthetic plate photos for the manual: coloured colonies on agar, and the
// same plate photographed again as its colonies appear and grow.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// One colony to draw: centre and radius in pixels, and its colour.
typedef Blob = ({double x, double y, double r, (int, int, int) rgb});

const kPhotoSize = 1200;
const kPlateRadius = 500.0;

/// White and blue (X-gal) colonies on dark amber agar.
const kWhite = (236, 233, 222);
const kBlue = (72, 112, 205);

/// [n] colony centres scattered over the plate, at least [gap] px apart.
List<(double, double)> scatter(int n, {int seed = 3, double gap = 34}) {
  final rnd = math.Random(seed);
  const c = kPhotoSize / 2;
  final out = <(double, double)>[];
  var tries = 0;
  while (out.length < n && tries++ < 50000) {
    final a = rnd.nextDouble() * 2 * math.pi;
    final d = math.sqrt(rnd.nextDouble()) * kPlateRadius * 0.86;
    final p = (c + d * math.cos(a), c + d * math.sin(a));
    if (out.every(
      (q) => math.pow(q.$1 - p.$1, 2) + math.pow(q.$2 - p.$2, 2) > gap * gap,
    )) {
      out.add(p);
    }
  }
  return out;
}

/// A plate photo: a round dish of agar on a dark bench, with [blobs].
Uint8List platePhoto(List<Blob> blobs, {int seed = 1}) {
  final rnd = math.Random(seed);
  const s = kPhotoSize, c = s / 2, r = kPlateRadius;
  final im = img.Image(width: s, height: s);
  for (var y = 0; y < s; y++) {
    for (var x = 0; x < s; x++) {
      final d = math.sqrt(math.pow(x - c, 2) + math.pow(y - c, 2));
      final n = rnd.nextDouble() * 4 - 2;
      if (d > r + 10) {
        im.setPixelRgb(x, y, 24 + n, 24 + n, 27 + n);
      } else if (d > r) {
        // The dish's rim.
        im.setPixelRgb(x, y, 78 + n, 78 + n, 80 + n);
      } else {
        final g = 1 + 0.08 * (x - c) / r - 0.06 * (y - c) / r;
        im.setPixelRgb(x, y, 104 * g + n, 84 * g + n, 48 * g + n);
      }
    }
  }
  for (final b in blobs) {
    for (var y = (b.y - b.r - 2).floor(); y <= (b.y + b.r + 2).ceil(); y++) {
      for (var x = (b.x - b.r - 2).floor(); x <= (b.x + b.r + 2).ceil(); x++) {
        if (x < 0 || y < 0 || x >= s || y >= s) continue;
        final d = math.sqrt(math.pow(x - b.x, 2) + math.pow(y - b.y, 2));
        final a = (b.r + 0.5 - d).clamp(0.0, 1.0);
        if (a <= 0) continue;
        // A little brighter in the middle, like a domed colony.
        final shade = 1.06 - 0.12 * d / b.r;
        final p = im.getPixel(x, y);
        double mix(num bg, int fg) =>
            (bg * (1 - a) + (fg * shade).clamp(0, 255) * a).toDouble();
        im.setPixelRgb(
          x,
          y,
          mix(p.r, b.rgb.$1),
          mix(p.g, b.rgb.$2),
          mix(p.b, b.rgb.$3),
        );
      }
    }
  }
  return Uint8List.fromList(img.encodeJpg(im, quality: 90));
}

/// A blue/white screening plate: [blue] of [n] colonies are blue.
Uint8List blueWhitePlate({int n = 60, int blue = 18, int seed = 3}) {
  final rnd = math.Random(seed + 1);
  final at = scatter(n, seed: seed);
  return platePhoto([
    for (var i = 0; i < at.length; i++)
      (
        x: at[i].$1,
        y: at[i].$2,
        r: 9 + rnd.nextDouble() * 4,
        rgb: i < blue ? kBlue : kWhite,
      ),
  ]);
}
