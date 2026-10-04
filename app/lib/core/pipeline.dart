import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'classical.dart';
import 'gray_image.dart';
import 'normalize.dart';
import 'plate.dart';

/// Above this many colonies a plate is "too numerous to count" for any preset.
const int kTntcCount = 300;
const double kTntcCoverage = 0.30;

/// Photos are analysed with their shorter side reduced to about this many pixels.
/// A 90 mm dish filling 80 % of the frame is then ~1400 px across (~65 µm/px).
const int kWorkShortSide = 1800;

class CountOptions {
  const CountOptions({
    this.plate,
    this.plateDiameterMm = kDefaultPlateDiameterMm,
    this.rimFraction = 0.95,
    this.polarity = Polarity.auto,
    this.params = const DetectParams(),
  });

  /// Use this plate circle instead of searching for it (e.g. after a manual fix),
  /// in original image pixels.
  final Plate? plate;
  final double plateDiameterMm;
  final double rimFraction;
  final Polarity polarity;
  final DetectParams params;
}

class CountResult {
  CountResult({
    required this.colonies,
    required this.plate,
    required this.polarity,
    required this.flags,
    required this.coverage,
    required this.imageWidth,
    required this.imageHeight,
  });

  final List<Colony> colonies;
  final Plate plate;
  final Polarity polarity;
  final List<String> flags;
  final double coverage;
  final int imageWidth;
  final int imageHeight;

  int get count => colonies.fold(0, (s, c) => s + c.n);
}

/// Counts colonies on a grayscale image (the plate and colonies are returned in
/// the same pixel coordinates as [gray]).
CountResult countColonies(
  GrayImage gray, [
  CountOptions o = const CountOptions(),
]) {
  final plate = o.plate ?? findPlate(gray, diameterMm: o.plateDiameterMm);
  final mask = plate.mask(gray.width, gray.height, rimFraction: o.rimFraction);
  final bg = estimateBackground(gray, plate);
  final (fg, polarity) = foreground(gray, bg, mask, polarity: o.polarity);
  final det = detect(fg, mask, plate.mmPerPx, o.params);

  final count = det.colonies.fold(0, (s, c) => s + c.n);
  final flags = <String>[
    if (det.spreaders > 0) 'spreader',
    if (count > kTntcCount || det.coverage > kTntcCoverage) 'tntc',
    if (det.colonies.any((c) => c.n > 1)) 'clusters_estimated',
  ];
  return CountResult(
    colonies: det.colonies,
    plate: plate,
    polarity: polarity,
    flags: flags,
    coverage: det.coverage,
    imageWidth: gray.width,
    imageHeight: gray.height,
  );
}

/// Converts a decoded colour image to luminance.
GrayImage grayFromImage(img.Image image) {
  final g = GrayImage(image.width, image.height);
  var i = 0;
  for (final p in image) {
    g.data[i++] = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
  }
  return g;
}

/// Decodes a photo (JPEG/PNG/...), applies its EXIF rotation, analyses a
/// downscaled copy and returns results in the photo's full-resolution pixels.
CountResult countPhoto(
  Uint8List bytes, [
  CountOptions o = const CountOptions(),
]) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('Unsupported image');
  final photo = img.bakeOrientation(decoded);
  final short = math.min(photo.width, photo.height);
  final scale = math.min(1.0, kWorkShortSide / short);
  final work = scale < 1
      ? img.copyResize(
          photo,
          width: (photo.width * scale).round(),
          height: (photo.height * scale).round(),
          interpolation: img.Interpolation.average,
        )
      : photo;
  final res = countColonies(
    grayFromImage(work),
    CountOptions(
      plate: o.plate?.scaled(scale),
      plateDiameterMm: o.plateDiameterMm,
      rimFraction: o.rimFraction,
      polarity: o.polarity,
      params: o.params,
    ),
  );
  final up = 1 / scale;
  return CountResult(
    colonies: [for (final c in res.colonies) c.scaled(up)],
    plate: res.plate.scaled(up),
    polarity: res.polarity,
    flags: res.flags,
    coverage: res.coverage,
    imageWidth: photo.width,
    imageHeight: photo.height,
  );
}
