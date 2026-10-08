import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'classical.dart';
import 'colour.dart';
import 'plate.dart';
import 'spots.dart';

/// Everything needed to draw an annotated copy of a plate photo.
class AnnotationJob {
  const AnnotationJob({
    required this.photo,
    required this.plate,
    required this.colonies,
    this.spots = const [],
    this.colourMode = ColourMode.none,
    this.header = const [],
    this.rimFraction = 0.95,
    this.maxSide = 2000,
  });

  /// Encoded photo (JPEG/PNG); colony coordinates are in its pixels.
  final Uint8List photo;
  final Plate plate;
  final List<Colony> colonies;
  final List<Spot> spots;
  final ColourMode colourMode;

  /// Lines for the banner across the top (sample, dilution, count…).
  final List<String> header;
  final double rimFraction;

  /// The output is scaled down to at most this many pixels on its long side.
  final int maxSide;
}

/// JPEG of the photo with the counted area, every colony mark, drops and a
/// header banner, for lab notebooks and reports. Same colours as the app:
/// green = automatic, pink = added by hand, orange = cluster (×N), blue/pink =
/// colour class 1.
Uint8List annotatePhoto(AnnotationJob job) {
  final decoded = img.decodeImage(job.photo);
  if (decoded == null) throw const FormatException('Unsupported image');
  var photo = img.bakeOrientation(decoded);
  final s = math.min(1.0, job.maxSide / math.max(photo.width, photo.height));
  if (s < 1) {
    photo = img.copyResize(
      photo,
      width: (photo.width * s).round(),
      height: (photo.height * s).round(),
      interpolation: img.Interpolation.average,
    );
  }
  final line = math.max(2, (math.max(photo.width, photo.height) / 700).round());

  void ring(double x, double y, double r, img.Color c, [int width = 0]) {
    final w = width == 0 ? line : width;
    for (var k = 0; k < w; k++) {
      img.drawCircle(
        photo,
        x: (x * s).round(),
        y: (y * s).round(),
        radius: (r * s).round() + k,
        color: c,
        antialias: true,
      );
    }
  }

  final cyan = img.ColorRgb8(0, 229, 255);
  final green = img.ColorRgb8(105, 240, 174);
  final pink = img.ColorRgb8(255, 64, 129);
  final orange = img.ColorRgb8(255, 171, 64);
  final blue = img.ColorRgb8(64, 196, 255);
  final amber = img.ColorRgb8(255, 215, 64);
  final black = img.ColorRgb8(0, 0, 0);
  final white = img.ColorRgb8(255, 255, 255);
  final grey = img.ColorRgb8(158, 158, 158);
  final font = photo.width >= 1400 ? img.arial48 : img.arial24;

  final p = job.plate;
  if (p.isSquare) {
    final pts = p.outline(rimFraction: job.rimFraction);
    for (var i = 0; i < pts.length; i++) {
      final (x0, y0) = pts[i];
      final (x1, y1) = pts[(i + 1) % pts.length];
      img.drawLine(
        photo,
        x1: (x0 * s).round(),
        y1: (y0 * s).round(),
        x2: (x1 * s).round(),
        y2: (y1 * s).round(),
        color: cyan,
        thickness: line,
        antialias: true,
      );
    }
  } else {
    ring(p.cx, p.cy, p.radius * job.rimFraction, cyan);
  }

  for (final c in job.colonies) {
    final r = math.max(c.radiusPx * 1.25, 4 / s);
    final colour = c.n > 1
        ? orange
        : c.manual
        ? pink
        : (job.colourMode != ColourMode.none && c.cls == 1)
        ? (job.colourMode == ColourMode.blueWhite ? blue : pink)
        : green;
    ring(c.x, c.y, r, colour);
    if (c.n > 1) {
      img.drawString(
        photo,
        'x${c.n}',
        font: img.arial24,
        x: ((c.x + r) * s).round() + 2,
        y: ((c.y) * s).round() - 12,
        color: orange,
      );
    }
  }

  for (var i = 0; i < job.spots.length; i++) {
    final sp = job.spots[i];
    final colour = sp.isExcluded ? grey : (sp.tntc ? pink : amber);
    ring(sp.cx, sp.cy, sp.radius, colour);
    final text =
        '${i + 1}: ${sp.tntc ? 'TNTC' : countInSpot(sp, job.colonies)}'
        '${sp.isExcluded ? ' (out)' : ''}';
    final x = ((sp.cx - sp.radius) * s).round();
    final y = ((sp.cy - sp.radius) * s).round() - font.lineHeight - 4;
    img.fillRect(
      photo,
      x1: x - 4,
      y1: y - 2,
      x2: x + text.length * font.base ~/ 2 + 8,
      y2: y + font.lineHeight + 2,
      color: colour,
    );
    img.drawString(photo, text, font: font, x: x, y: y, color: black);
  }

  if (job.header.isNotEmpty) {
    final h = job.header.length * (font.lineHeight + 6) + 12;
    img.fillRect(
      photo,
      x1: 0,
      y1: 0,
      x2: photo.width - 1,
      y2: h,
      color: img.ColorRgba8(0, 0, 0, 190),
      alphaBlend: true,
    );
    for (var i = 0; i < job.header.length; i++) {
      img.drawString(
        photo,
        asciiOnly(job.header[i]),
        font: font,
        x: 12,
        y: 8 + i * (font.lineHeight + 6),
        color: white,
      );
    }
  }
  return Uint8List.fromList(img.encodeJpg(photo, quality: 90));
}

/// The bitmap fonts only cover ASCII: write superscripts and symbols plainly.
String asciiOnly(String s) {
  const map = {
    '⁰': '0',
    '¹': '1',
    '²': '2',
    '³': '3',
    '⁴': '4',
    '⁵': '5',
    '⁶': '6',
    '⁷': '7',
    '⁸': '8',
    '⁹': '9',
    '⁻': '-',
    '₀': '0',
    '₁': '1',
    '×': 'x',
    '·': '-',
    '–': '-',
    '—': '-',
    '±': '+/-',
    'µ': 'u',
    '…': '...',
  };
  final out = StringBuffer();
  var inSup = false;
  for (final ch in s.split('')) {
    final isSup = '⁰¹²³⁴⁵⁶⁷⁸⁹⁻'.contains(ch);
    if (isSup && !inSup) out.write('^');
    inSup = isSup;
    final m = map[ch];
    if (m != null) {
      out.write(m);
    } else if (ch.codeUnitAt(0) < 128) {
      out.write(ch);
    } else {
      out.write('?');
    }
  }
  return out.toString();
}
