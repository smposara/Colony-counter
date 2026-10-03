import 'dart:math' as math;
import 'dart:typed_data';

import 'gray_image.dart';
import 'plate.dart';

/// Smooth background of the agar, ignoring colonies (see ml/colonycounter/normalize.py).
///
/// A median filter much wider than a colony follows lighting gradients but not the
/// colonies. It runs on a copy downscaled to [workPxPerMm] for speed; pixels outside
/// the plate are first filled with the agar median so the surround does not bleed in.
GrayImage estimateBackground(
  GrayImage gray,
  Plate plate, {
  double kernelMm = 6.0,
  double workPxPerMm = 4.0,
}) {
  final inside = plate.mask(gray.width, gray.height, rimFraction: 0.97);
  final sample = <double>[];
  for (var i = 0; i < inside.length; i += 7) {
    if (inside[i] == 1) sample.add(gray.data[i]);
  }
  final agarMedian = median(sample);
  final filled = gray.copy();
  for (var i = 0; i < inside.length; i++) {
    if (inside[i] == 0) filled.data[i] = agarMedian;
  }

  final scale = math.min(1.0, workPxPerMm * plate.mmPerPx);
  final small = filled.resize(
    math.max(1, (gray.width * scale).round()),
    math.max(1, (gray.height * scale).round()),
  );
  var k = (kernelMm / plate.mmPerPx * scale).round() | 1;
  k = k.clamp(3, 255);
  final bg = small.medianFilter(k).gaussianBlur(math.max(1.0, k / 6));
  return bg.resize(gray.width, gray.height);
}

enum Polarity { auto, bright, dark }

/// Signed contrast map where colonies are positive, plus the polarity used.
///
/// [Polarity.bright]: colonies lighter than agar (dark-field lightbox).
/// [Polarity.dark]: colonies darker (back-lit). [Polarity.auto] picks by comparing
/// the bright and dark tails of the contrast distribution.
(GrayImage, Polarity) foreground(
  GrayImage gray,
  GrayImage background,
  Uint8List mask, {
  Polarity polarity = Polarity.auto,
}) {
  final diff = GrayImage(gray.width, gray.height);
  for (var i = 0; i < diff.data.length; i++) {
    diff.data[i] = gray.data[i] - background.data[i];
  }
  if (polarity == Polarity.auto) {
    final vals = <double>[];
    for (var i = 0; i < mask.length; i += 3) {
      if (mask[i] == 1) vals.add(diff.data[i]);
    }
    vals.sort();
    final hi = percentileSorted(vals, 99.7);
    final lo = -percentileSorted(vals, 0.3);
    polarity = hi >= lo ? Polarity.bright : Polarity.dark;
  }
  final sign = polarity == Polarity.dark ? -1.0 : 1.0;
  for (var i = 0; i < diff.data.length; i++) {
    diff.data[i] = mask[i] == 1 ? diff.data[i] * sign : 0;
  }
  return (diff, polarity);
}
