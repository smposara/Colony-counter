import 'dart:io';
import 'dart:typed_data';

import 'package:colony_counter/core/annotate.dart';
import 'package:colony_counter/core/labels.dart';
import 'package:colony_counter/core/pipeline.dart';
import 'package:colony_counter/core/plate.dart';
import 'package:colony_counter/core/worker/protocol.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('QR worker reads the same sample, dilution and replicate', () {
    const label = PlateLabel('Lake A', dilutionExp: 4, replicate: 2);
    final bytes = Uint8List.fromList(img.encodePng(renderLabelQr(label)));
    final result = processPhotoJob(bytes, {'kind': 'label'});
    expect(result['label'], label.encode());
  });
  test(
    'annotation worker returns the same JPEG bytes without JSON byte arrays',
    () {
      final bytes = File('test/fixtures/sparse.jpg').readAsBytesSync();
      final result = countPhoto(bytes);
      final job = AnnotationJob(
        photo: bytes,
        plate: result.plate,
        colonies: result.colonies,
        header: ['sample 40 CFU'],
      );
      final actual = processPhotoJob(bytes, annotationJob(job));
      expect(actual['binary'], annotatePhoto(job));
    },
  );
  test('multi-plate detection and cropping match the native pipeline', () {
    final bytes = File('test/fixtures/sparse.jpg').readAsBytesSync();
    final result = findPlatesInPhoto((bytes, PlateFormat.dish90));
    final found = processPhotoJob(bytes, {
      'kind': 'find_plates',
      'format': 'dish90',
    });
    expect(found['plates'], [for (final p in result.plates) p.toJson()]);
    final plate = countPhoto(bytes).plate;
    final expected = cropToPlate((bytes, plate));
    final crop = processPhotoJob(bytes, {
      'kind': 'crop',
      'plate': plate.toJson(),
    });
    expect(crop['binary'], expected.$1);
    expect(crop['plate'], expected.$2.toJson());
  });
}
