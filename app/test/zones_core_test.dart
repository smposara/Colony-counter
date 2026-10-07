import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:colony_counter/core/plate.dart';
import 'package:colony_counter/core/zones.dart';
import 'package:flutter_test/flutter_test.dart';

// Golden plates from ml/scripts/make_app_fixtures.py --zones: true diameters
// and the Python reference result on the same JPEG.
const zoneFixtures = [
  'zones_reflected',
  'zones_backlit_hazy',
  'zones_wells',
  'zones_nozone',
  'zones_overlap',
];

Map<String, dynamic> _label(String name) =>
    jsonDecode(File('test/fixtures/$name.json').readAsStringSync())
        as Map<String, dynamic>;

ZoneResult _measure(String name, Map<String, dynamic> label) =>
    measureZonesInPhoto((
      File('test/fixtures/$name.jpg').readAsBytesSync(),
      ZoneOptions(
        format: PlateFormat.dish90,
        assay: label['assay'] == 'well' ? ZoneAssay.well : ZoneAssay.disk,
        diskMm: (label['disk_mm'] as num).toDouble(),
      ),
    ));

/// The measured zone at (x, y), within 2 mm of the disk centre.
Zone? _at(ZoneResult r, Map<String, dynamic> p, double mmPerPx) {
  Zone? best;
  var bestD = 2 / mmPerPx;
  for (final z in r.zones) {
    final d = math.sqrt(
      math.pow(z.x - (p['x'] as num), 2) + math.pow(z.y - (p['y'] as num), 2),
    );
    if (d < bestD) {
      best = z;
      bestD = d;
    }
  }
  return best;
}

void main() {
  group('zone detector on golden plates', () {
    for (final name in zoneFixtures) {
      test(name, () {
        final label = _label(name);
        final python = label['python'] as Map<String, dynamic>;
        final res = _measure(name, label);
        final mm = 90 / (2 * (label['plate']['radius'] as num));

        expect(res.polarity, python['polarity']);
        expect(res.flags, python['flags']);
        expect(
          res.zones.length,
          (label['true'] as List).length,
          reason: 'one zone per disk',
        );

        // Accuracy against ground truth. Zones reaching < 1 mm past the disk
        // read as "no zone" (a known limit); hazy edges get 1 mm.
        final hazy = name.contains('hazy');
        for (final t in (label['true'] as List).cast<Map<String, dynamic>>()) {
          final z = _at(res, t, mm);
          expect(z, isNotNull, reason: 'disk at ${t['x']}, ${t['y']}');
          final truth = (t['diameter_mm'] as num).toDouble();
          if (truth < 8) continue;
          expect(
            (z!.diameterMm - truth).abs(),
            lessThanOrEqualTo(hazy ? 1.0 : 0.5),
            reason: 'Dart ${z.diameterMm} vs truth $truth',
          );
        }
        // Agreement with the Python reference implementation.
        for (final p
            in (python['zones'] as List).cast<Map<String, dynamic>>()) {
          final z = _at(res, p, mm);
          expect(z, isNotNull, reason: 'Python zone at ${p['x']}, ${p['y']}');
          final pmm = p['diameter_mm'] as num?;
          if (pmm == null) {
            expect(z!.measured, isFalse);
            continue;
          }
          expect(
            (z!.diameterMm - pmm).abs(),
            lessThanOrEqualTo(0.3),
            reason: 'Dart ${z.diameterMm} vs Python $pmm',
          );
          expect(
            z.flags.toSet(),
            (p['flags'] as List).toSet(),
            reason: 'flags at ${p['x']}, ${p['y']}',
          );
        }
      });
    }
  });

  test('given plate and disks skip detection', () {
    final label = _label('zones_nozone');
    final bytes = File('test/fixtures/zones_nozone.jpg').readAsBytesSync();
    final first = measureZonesInPhoto((bytes, const ZoneOptions()));
    final keep = first.zones
        .take(2)
        .map((z) => Disk(z.x, z.y, z.diskRadiusPx))
        .toList();
    final again = measureZonesInPhoto((
      bytes,
      ZoneOptions(plate: first.plate, disks: keep),
    ));
    expect(again.zones.length, 2);
    for (var i = 0; i < 2; i++) {
      expect(
        again.zones[i].diameterMm,
        closeTo(first.zones[i].diameterMm, 0.3),
      );
    }
    expect(label['assay'], 'disk');
  });

  test('a wrong plate size is reported', () {
    final bytes = File('test/fixtures/zones_reflected.jpg').readAsBytesSync();
    final r = measureZonesInPhoto((
      bytes,
      const ZoneOptions(format: PlateFormat.dish100),
    ));
    expect(r.flags, contains('scale_mismatch'));
  });

  test('rounding to whole mm and JSON round trip', () {
    Zone z(double mm) => Zone(
      x: 1,
      y: 2,
      diskRadiusPx: 3,
      radiusPx: 10,
      diameterMm: mm,
      confidence: 0.9,
      edgeWidthMm: 0.4,
      flags: ['hazy'],
    );
    expect(z(22.5).diameterRounded, 23);
    expect(z(22.49).diameterRounded, 22);
    expect(z(double.nan).diameterRounded, isNull);
    final back = Zone.fromJson(z(18.25).toJson());
    expect(back.diameterMm, 18.25);
    expect(back.flags, ['hazy']);
    final un = Zone.fromJson(z(double.nan).toJson());
    expect(un.measured, isFalse);
  });
}
