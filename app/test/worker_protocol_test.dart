import 'dart:convert';
import 'dart:io';

import 'package:colony_counter/core/classical.dart';
import 'package:colony_counter/core/drop_layout.dart';
import 'package:colony_counter/core/petrifilm.dart';
import 'package:colony_counter/core/plate.dart';
import 'package:colony_counter/core/zones.dart';
import 'package:colony_counter/core/image_limits.dart';
import 'package:colony_counter/core/pipeline.dart';
import 'package:colony_counter/core/worker/protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'worker count matches the native pipeline and preserves tuning/coordinates',
    () {
      final bytes = File('test/fixtures/sparse.jpg').readAsBytesSync();
      const options = CountOptions(params: DetectParams(kSigma: 3.7));
      final expected = countPhoto(bytes, options);
      final wire = jsonDecode(
        jsonEncode(processPhotoJob(bytes, countJob(options))),
      ) as Map<String, dynamic>;
      final actual = readCount(wire);
      expect(actual.count, expected.count);
      expect(actual.imageWidth, expected.imageWidth);
      expect(actual.plate.toJson(), expected.plate.toJson());
      expect(actual.flags, expected.flags);
      expect(actual.colonies.first.x, expected.colonies.first.x);
    },
  );

  test('panoramic work images respect dimensions and pixel budget', () {
    for (final size in [
      (12000, 1000),
      (4000, 3000),
      (1000, 12000),
      (800, 800),
    ]) {
      final s = analysisScale(size.$1, size.$2);
      expect(size.$1 * s, lessThanOrEqualTo(kMaxWorkSide));
      expect(size.$2 * s, lessThanOrEqualTo(kMaxWorkSide));
      expect(size.$1 * size.$2 * s * s, lessThanOrEqualTo(kMaxWorkPixels + 1));
    }
  });
  test('film worker codec preserves results, grid and dimensions', () {
    final bytes = File('test/fixtures/film_ac.jpg').readAsBytesSync();
    final job = FilmJob(bytes, 'ac');
    final expected = countFilmJob(job);
    final actual = readFilm(
      jsonDecode(jsonEncode(processPhotoJob(bytes, filmJob(job))))
          as Map<String, dynamic>,
    );
    expect(actual.counts, expected.counts);
    expect(actual.grid.toJson(), expected.grid.toJson());
    expect(actual.imageWidth, expected.imageWidth);
    expect(actual.colonies.length, expected.colonies.length);
  });

  test('drop worker codec preserves layout, counts and assignments', () {
    final bytes = File('test/fixtures/drops_sectors8.jpg').readAsBytesSync();
    final DropJob job = (
      bytes,
      const SectorTemplate(),
      [3, 4, 5, 6, 7, 8, 9, 10],
      10,
      PlateFormat.dish90,
      null,
    );
    final expected = countDropPlateInPhoto(job);
    final actual = readDrop(
      jsonDecode(jsonEncode(processPhotoJob(bytes, dropJob(job))))
          as Map<String, dynamic>,
    );
    expect(
      actual.drops.map((d) => d.count),
      expected.drops.map((d) => d.count),
    );
    expect(
      actual.drops.map((d) => d.colonies),
      expected.drops.map((d) => d.colonies),
    );
    expect(actual.flags, expected.flags);
    expect(actual.imageWidth, expected.imageWidth);
  });

  test(
    'zone worker codec preserves missing edges and measurement warnings',
    () {
      final bytes = File('test/fixtures/zones_nozone.jpg').readAsBytesSync();
      const options = ZoneOptions();
      final expected = measureZonesInPhoto((bytes, options));
      final actual = readZones(
        jsonDecode(jsonEncode(processPhotoJob(bytes, zoneJob(options))))
            as Map<String, dynamic>,
      );
      expect(
        actual.zones.map((z) => z.toJson()),
        expected.zones.map((z) => z.toJson()),
      );
      expect(actual.diskScaleRatio, expected.diskScaleRatio);
      expect(actual.flags, expected.flags);
    },
  );
}
