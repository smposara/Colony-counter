import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../core/zone_calibration.dart';
import 'plate_store.dart';
import 'zone_calibration_record.dart';
import 'zone_record.dart';

/// The zone feature's real-photo gate (docs/AST.md): on at least this many
/// plates measured with a calliper, mean error ≤ 1 mm and ≥ 95 % within ±2 mm.
const int kGatePlates = 30;
const double kGateMeanError = 1.0;
const double kGateWithin2 = 0.95;

/// Progress towards the gate, pooled over every calliper calibration.
class GateProgress {
  const GateProgress({
    required this.plates,
    required this.zones,
    required this.meanAbsError,
    required this.within2mm,
  });

  final int plates;
  final int zones;

  /// Mean |app − calliper| in mm (NaN with no zones).
  final double meanAbsError;

  /// Fraction of zones within ±2 mm.
  final double within2mm;

  bool get enoughPlates => plates >= kGatePlates;

  /// The gate's limits are met on enough plates. The beta label is only
  /// dropped by a release, never by the app itself.
  bool get met =>
      enoughPlates &&
      meanAbsError <= kGateMeanError &&
      within2mm >= kGateWithin2;
}

GateProgress gateProgress(List<CalibrationProfile> profiles) {
  final plates = <String>{};
  final diffs = <double>[];
  // A plate in several profiles counts once: its newest snapshot.
  final newest = <String, CalibrationPlate>{};
  for (final p in profiles) {
    if (p.tool != CalibrationTool.calliper) continue;
    for (final plate in p.plates) {
      final had = newest[plate.zoneRecordId];
      if (had == null || plate.addedAt.isAfter(had.addedAt)) {
        newest[plate.zoneRecordId] = plate;
      }
    }
  }
  for (final plate in newest.values) {
    var used = false;
    for (final z in plate.zones) {
      if (!z.included || z.appMm.isEmpty || z.userMm.isEmpty) continue;
      final app = z.appMm.reduce((a, b) => a + b) / z.appMm.length;
      final user = z.userMm.reduce((a, b) => a + b) / z.userMm.length;
      diffs.add((app - user).abs());
      used = true;
    }
    if (used) plates.add(plate.zoneRecordId);
  }
  return GateProgress(
    plates: plates.length,
    zones: diffs.length,
    meanAbsError: diffs.isEmpty
        ? double.nan
        : diffs.reduce((a, b) => a + b) / diffs.length,
    within2mm: diffs.isEmpty
        ? double.nan
        : diffs.where((d) => d <= 2 + 1e-9).length / diffs.length,
  );
}

/// Calibration plates with the photo and a label for each, as
/// `colonycounter evaluate-zones` reads them: `<photo>.jpg` next to
/// `<photo>.json` with the calliper diameters per disk, plus `profiles.json`
/// and a README. Opt-in: the user shares it.
Future<Uint8List> buildCalibrationTestData(PlateStore store) async {
  final archive = Archive();
  void addText(String name, String text) {
    final bytes = utf8.encode(text);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  final records = {for (final r in store.zoneRecords) r.id: r};
  final written = <String>{};
  for (final profile in store.calibrations) {
    for (final plate in profile.plates) {
      final r = records[plate.zoneRecordId];
      if (r == null || !written.add(r.id)) continue;
      final photo = await store.readPhotoPath(r.imagePath);
      if (photo == null) continue;
      final stem = r.imagePath.endsWith('.jpg')
          ? r.imagePath.substring(0, r.imagePath.length - 4)
          : r.imagePath;
      archive.addFile(ArchiveFile.noCompress('$stem.jpg', photo.length, photo));
      addText(
        '$stem.json',
        const JsonEncoder.withIndent(' ')
            .convert(calibrationLabel(r, plate, profile)),
      );
    }
  }
  final gate = gateProgress(store.calibrations);
  addText(
    'profiles.json',
    const JsonEncoder.withIndent(' ').convert({
      'format': 'colony-counter-zone-calibration',
      'version': 1,
      'created_at': DateTime.now().toIso8601String(),
      'gate': {
        'plates': gate.plates,
        'zones': gate.zones,
        'mean_abs_error_mm': _r3(gate.meanAbsError),
        'within_2mm': _r3(gate.within2mm),
        'met': gate.met,
      },
      'profiles': [
        for (final p in store.calibrations)
          {...p.toJson(), 'summary': _summaryJson(p.summary)},
      ],
    }),
  );
  addText('README.txt', _readme);
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// The label of one calibration plate (see [buildCalibrationTestData]).
/// The label of one calibration plate (see [buildCalibrationTestData]).
/// Positions come from the snapshot, as the plate was when it was measured: the
/// record's marks may since have been added, deleted or measured again.
Map<String, dynamic> calibrationLabel(
  ZoneRecord r,
  CalibrationPlate plate,
  CalibrationProfile profile,
) {
  /// The record's mark at (x, y) now, if one is still there.
  ZoneMark? markAt(double x, double y) {
    ZoneMark? best;
    var bestD = double.infinity;
    for (final m in r.marks) {
      final d = math.sqrt(math.pow(m.x - x, 2) + math.pow(m.y - y, 2));
      if (d <= math.max(m.diskRadiusPx, 1) * 1.5 && d < bestD) {
        best = m;
        bestD = d;
      }
    }
    return best;
  }

  Map<String, dynamic>? zone(CalibrationZone z) {
    // Snapshots from before positions were kept fall back to the mark index.
    final old = z.mark < r.marks.length ? r.marks[z.mark] : null;
    final x = z.x ?? old?.x, y = z.y ?? old?.y;
    if (x == null || y == null) return null;
    final m = markAt(x, y);
    final label = z.x != null ? z.label : (old?.label ?? '');
    return {
      'x': _r1(x),
      'y': _r1(y),
      'diameter_mm': _r2(z.userMm.reduce((a, b) => a + b) / z.userMm.length),
      'readings_mm': z.userMm,
      'app_mm': z.appMm.isEmpty ? null : _r2(z.appMm.first),
      if (label.isNotEmpty) 'label': label,
      if (m != null && m.flags.isNotEmpty) 'flags': m.flags,
      if (m != null && m.noZone) 'no_zone': true,
    };
  }

  List<Map<String, dynamic>>? spanDisks() {
    final sd = plate.spanDisks;
    if (sd != null) {
      return [
        for (final (x, y) in [sd.$1, sd.$2]) {'x': _r1(x), 'y': _r1(y)},
      ];
    }
    final sm = plate.spanMarks;
    if (sm == null || sm.$1 >= r.marks.length || sm.$2 >= r.marks.length) {
      return null;
    }
    return [
      for (final i in [sm.$1, sm.$2])
        {'x': _r1(r.marks[i].x), 'y': _r1(r.marks[i].y)},
    ];
  }

  final span = spanDisks();
  final user = plate.userSpanMm;
  return {
    'plate_mm': r.format.sizeMm,
    'assay': r.assay.name,
    'disk_mm': r.diskMm,
    'tool': profile.tool.name,
    if (span != null && user != null && user > 0) ...{
      'span_mm': user,
      'span_disks': span,
    },
    'camera': profile.cameraName,
    'setup': profile.setup.name,
    'platform': profile.platform,
    'profile': profile.id,
    'image_width': r.imageWidth,
    'image_height': r.imageHeight,
    'photographed_at': r.createdAt.toIso8601String(),
    'zones': [
      for (final z in plate.zones)
        if (z.included) ?zone(z),
    ],
    'excluded': [
      for (final z in plate.zones)
        if (!z.included) ?zone(z),
    ],
  };
}

Map<String, dynamic> _summaryJson(CalSummary s) => {
  'n': s.n,
  'bias_mm': _r3(s.bias),
  'sd_mm': _r3(s.sd),
  'limits_of_agreement_mm': [_r3(s.loaLow), _r3(s.loaHigh)],
  'within_1mm': _r3(s.within1mm),
  'scale_error': _r3(s.scaleError),
  'verdict': s.verdict.name,
  'hint': s.hint.name,
};

double? _r(double? v, int d) {
  if (v == null || !v.isFinite) return null;
  final k = math.pow(10, d);
  return (v * k).round() / k;
}

double? _r1(double v) => _r(v, 1);
double? _r2(double v) => _r(v, 2);
double? _r3(double? v) => _r(v, 3);

const _readme = '''Colony Counter: zone calibration test data

Each calibration plate is a photo (<name>.jpg) and a label (<name>.json):
  zones[].x, y        disk or well centre, photo pixels
  zones[].diameter_mm the user's calliper (or ruler) reading, the mean of
                      readings_mm (two readings at right angles for a zone
                      that isn't round)
  zones[].app_mm      what the app measured when the plate was calibrated
  excluded[]          zones the user left out (hazy, overlapping, no zone...)
  span_mm, span_disks the user's outer-edge to outer-edge reading across the
                      two disks farthest apart (the scale check)
  tool, camera, setup how it was measured and photographed

profiles.json holds every calibration with its summary, and the progress
towards the zone feature's real-photo gate (30 or more plates measured with a
calliper: mean error <= 1 mm and >= 95 % within 2 mm).

To score the detector on a computer:
  pip install -e "ml[dev]"
  colonycounter evaluate-zones <this folder>

Measurement only: no susceptible / intermediate / resistant interpretation.
''';
