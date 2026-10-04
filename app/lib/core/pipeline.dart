import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'classical.dart';
import 'colour.dart';
import 'gray_image.dart';
import 'grid.dart';
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
    this.format = PlateFormat.dish90,
    this.rimFraction = 0.95,
    this.polarity = Polarity.auto,
    this.params = const DetectParams(),
  });

  /// Use this plate circle instead of searching for it (e.g. after a manual fix),
  /// in original image pixels.
  final Plate? plate;

  /// Dish or filter type: its size sets the scale, its shape the plate finder.
  final PlateFormat format;
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
  final plate = o.plate ?? findPlate(gray, format: o.format);
  final mask = plate.mask(gray.width, gray.height, rimFraction: o.rimFraction);
  final bg = estimateBackground(gray, plate);
  var (fg, polarity) = foreground(gray, bg, mask, polarity: o.polarity);
  if (o.format.membrane) fg = suppressGridLines(fg, mask, plate.mmPerPx);
  final det = detect(fg, mask, plate.mmPerPx, o.params);

  final count = det.colonies.fold(0, (s, c) => s + c.n);
  final tntc = count > kTntcCount || det.coverage > kTntcCoverage;
  final flags = <String>[
    if (det.spreaders > 0) 'spreader',
    if (tntc) 'tntc',
    if (det.colonies.any((c) => c.n > 1)) 'clusters_estimated',
    if (!tntc) ...confidenceWarnings(det, plate, mask),
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

/// Flags that mean "check this count by eye" (see [confidenceWarnings]).
const kCheckFlags = {
  'spreader',
  'tntc',
  'crowded',
  'many_clusters',
  'low_contrast',
};

/// Colonies per cm² above which neighbours start to merge (about 220 on a
/// 90 mm dish).
const double kCrowdedPerCm2 = 3.5;

/// Situations where the automatic count is often wrong:
/// - `crowded`: dense plate, so touching colonies merge;
/// - `many_clusters`: over 15 % of the count comes from estimated clusters;
/// - `low_contrast`: over 35 % of colonies are barely above the threshold, so
///   small changes in lighting or sensitivity change the count.
List<String> confidenceWarnings(Detection det, Plate plate, Uint8List mask) {
  final cols = det.colonies;
  final count = cols.fold(0, (s, c) => s + c.n);
  if (count == 0) return const [];
  var area = 0;
  for (final m in mask) {
    area += m;
  }
  final cm2 = area * plate.mmPerPx * plate.mmPerPx / 100;
  final clustered = cols.where((c) => c.n > 1).fold(0, (s, c) => s + c.n);
  final thr = det.threshold / det.noiseSigma;
  final faint = cols.where((c) => c.score < 1.5 * thr).length;
  return [
    if (cm2 > 0 && count / cm2 > kCrowdedPerCm2) 'crowded',
    if (count >= 10 && clustered > 0.15 * count) 'many_clusters',
    if (cols.length >= 5 && faint > 0.35 * cols.length) 'low_contrast',
  ];
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
      format: o.format,
      rimFraction: o.rimFraction,
      polarity: o.polarity,
      params: o.params,
    ),
  );
  final up = 1 / scale;
  final full = [for (final c in res.colonies) c.scaled(up)];
  final colours = colonyColours(photo, full);
  return CountResult(
    colonies: [
      for (var i = 0; i < full.length; i++) full[i].withColour(colours[i]),
    ],
    plate: res.plate.scaled(up),
    polarity: res.polarity,
    flags: res.flags,
    coverage: res.coverage,
    imageWidth: photo.width,
    imageHeight: photo.height,
  );
}

/// Plates found in a photo with several dishes, in the photo's pixels.
class PlatesInPhoto {
  const PlatesInPhoto(this.plates, this.width, this.height);

  final List<Plate> plates;
  final int width;
  final int height;
}

/// Finds every round plate in a photo (see [findPlates]). Takes a record so
/// it can run in a background isolate with `compute`.
PlatesInPhoto findPlatesInPhoto((Uint8List, PlateFormat) job) {
  final decoded = img.decodeImage(job.$1);
  if (decoded == null) throw const FormatException('Unsupported image');
  final photo = img.bakeOrientation(decoded);
  final scale = math.min(1.0, 1200 / math.max(photo.width, photo.height));
  final work = img.copyResize(
    photo,
    width: (photo.width * scale).round(),
    height: (photo.height * scale).round(),
    interpolation: img.Interpolation.average,
  );
  final plates = findPlates(grayFromImage(work), format: job.$2);
  return PlatesInPhoto(
    [for (final p in plates) p.scaled(1 / scale)],
    photo.width,
    photo.height,
  );
}

/// Cuts one plate out of a photo with a small margin, as a JPEG, and returns
/// the plate's position in the cut-out.
(Uint8List, Plate) cropToPlate((Uint8List, Plate) job) {
  final photo = img.bakeOrientation(img.decodeImage(job.$1)!);
  final p = job.$2;
  final half = p.radius * (p.isSquare ? math.sqrt2 : 1) * 1.08;
  final x0 = math.max(0, (p.cx - half).floor());
  final y0 = math.max(0, (p.cy - half).floor());
  final x1 = math.min(photo.width, (p.cx + half).ceil());
  final y1 = math.min(photo.height, (p.cy + half).ceil());
  final crop = img.copyCrop(
    photo,
    x: x0,
    y: y0,
    width: x1 - x0,
    height: y1 - y0,
  );
  return (
    Uint8List.fromList(img.encodeJpg(crop, quality: 92)),
    p.copyWith(cx: p.cx - x0, cy: p.cy - y0),
  );
}
