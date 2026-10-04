import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../core/classical.dart';
import 'plate_record.dart';
import 'plate_store.dart';

/// Which plates go into a training export.
enum TrainingSelection {
  /// Plates checked colony by colony: complete labels.
  checked('Checked plates only'),

  /// Checked plates plus any plate the user corrected: labels are complete
  /// where the user looked, but may miss colonies nobody checked.
  corrected('Checked and corrected plates'),

  /// Every saved plate, including uncorrected automatic counts.
  all('All plates');

  const TrainingSelection(this.label);
  final String label;
}

bool _corrected(PlateRecord r) =>
    r.rejected.isNotEmpty ||
    r.colonies.any((c) => c.manual) ||
    r.count != r.autoCount;

/// Plates matching [selection], newest first.
List<PlateRecord> trainingPlates(
  PlateStore store,
  TrainingSelection selection,
) => [
  for (final r in store.records)
    if (switch (selection) {
      TrainingSelection.checked => r.verified,
      TrainingSelection.corrected => r.verified || _corrected(r),
      TrainingSelection.all => true,
    })
      r,
];

/// The user's corrections as a labelled dataset for training a colony
/// detector, in two common formats:
///
/// - `annotations.json`: COCO-style boxes (category 1 = colony, 2 = cluster of
///   several), with each mark's source (automatic or added by hand), colony
///   count and colour class. `rejected` lists automatic detections the user
///   removed: hard negative examples. Each image also has its plate outline and
///   scale (mm per pixel).
/// - `labels/<id>.txt`: YOLO boxes (class 0 = colony, 1 = cluster),
///   normalised to the image size.
/// - `images/<id>.jpg`: the photos.
Future<Uint8List> buildTrainingExport(
  PlateStore store, {
  TrainingSelection selection = TrainingSelection.corrected,
}) async {
  final archive = Archive();
  final images = <Map<String, dynamic>>[];
  final annotations = <Map<String, dynamic>>[];
  final rejected = <Map<String, dynamic>>[];
  var annId = 1;

  List<double> box(Colony c) {
    final r = math.max(c.radiusPx * 1.1, 3.0);
    return [c.x - r, c.y - r, 2 * r, 2 * r];
  }

  for (final r in trainingPlates(store, selection)) {
    final bytes = await store.readPhoto(r);
    if (bytes == null) continue;
    final imageId = images.length + 1;
    final dot = r.imagePath.lastIndexOf('.');
    final ext = dot < 0 ? 'jpg' : r.imagePath.substring(dot + 1);
    final file = 'images/${r.id}.$ext';
    archive.addFile(ArchiveFile.noCompress(file, bytes.length, bytes));
    images.add({
      'id': imageId,
      'file_name': file,
      'width': r.imageWidth,
      'height': r.imageHeight,
      'plate_id': r.id,
      'plate': r.plate.toJson(),
      'plate_type': r.format.name,
      'mm_per_px': r.plate.mmPerPx,
      'checked': r.verified,
      'corrected': _corrected(r),
      'auto_count': r.autoCount,
      'count': r.count,
      'colour_mode': r.colourMode.name,
      'flags': r.flags,
    });
    final yolo = StringBuffer();
    for (final c in r.colonies) {
      final b = box(c);
      final cluster = c.n > 1;
      annotations.add({
        'id': annId++,
        'image_id': imageId,
        'category_id': cluster ? 2 : 1,
        'bbox': [for (final v in b) _r2(v)],
        'area': _r2(b[2] * b[3]),
        'iscrowd': 0,
        'center': [_r2(c.x), _r2(c.y)],
        'radius': _r2(c.radiusPx),
        'n': c.n,
        'source': c.manual ? 'manual' : 'auto',
        'colour_class': c.cls,
      });
      final w = r.imageWidth.toDouble(), h = r.imageHeight.toDouble();
      yolo.writeln(
        '${cluster ? 1 : 0} ${_f6((b[0] + b[2] / 2) / w)} ${_f6((b[1] + b[3] / 2) / h)} '
        '${_f6(b[2] / w)} ${_f6(b[3] / h)}',
      );
    }
    for (final c in r.rejected) {
      rejected.add({
        'image_id': imageId,
        'bbox': [for (final v in box(c)) _r2(v)],
        'center': [_r2(c.x), _r2(c.y)],
        'radius': _r2(c.radiusPx),
      });
    }
    final txt = utf8.encode(yolo.toString());
    archive.addFile(ArchiveFile('labels/${r.id}.txt', txt.length, txt));
  }

  final coco = utf8.encode(
    const JsonEncoder.withIndent(' ').convert({
      'info': {
        'description': 'Colony Counter training export',
        'selection': selection.name,
        'date_created': DateTime.now().toIso8601String(),
      },
      'categories': [
        {'id': 1, 'name': 'colony'},
        {'id': 2, 'name': 'cluster'},
      ],
      'images': images,
      'annotations': annotations,
      'rejected': rejected,
    }),
  );
  archive.addFile(ArchiveFile('annotations.json', coco.length, coco));
  final readme = utf8.encode(_readme(selection, images.length));
  archive.addFile(ArchiveFile('README.txt', readme.length, readme));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

double _r2(double v) => (v * 100).round() / 100;
String _f6(double v) => v.clamp(0.0, 1.0).toStringAsFixed(6);

String _readme(TrainingSelection selection, int n) =>
    '''
Colony Counter training export
==============================

$n plate photo(s); selection: ${selection.label}.

images/<id>.jpg     the photos (as saved by the app)
labels/<id>.txt     YOLO boxes: class cx cy w h (0-1). Class 0 = colony,
                    1 = cluster of several colonies (see "n" in the JSON)
annotations.json    COCO-style: images, annotations (bbox = x, y, w, h in
                    pixels), categories, plus:
                      images[].plate      plate outline (centre, radius, shape)
                      images[].mm_per_px  scale
                      images[].checked    every colony was checked by hand
                      annotations[].source  "auto" (kept automatic mark) or
                                            "manual" (added by hand)
                      rejected[]          automatic marks the user removed
                                          (false positives; hard negatives)

Colonies outside the plate outline were not counted and are not labelled.
On plates that were corrected but not checked, unlabelled colonies may
remain; prefer checked plates for evaluation.
Read it in Python with ml/colonycounter/app_export.py.
''';
