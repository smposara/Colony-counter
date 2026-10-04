import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../core/calculator.dart';
import '../core/spots.dart';
import 'plate_record.dart';
import 'plate_store.dart';
import 'sample_info.dart';

String _csv(List<List<Object?>> rows) {
  String esc(Object? v) {
    final s = v == null ? '' : (v is double && !v.isFinite ? '' : '$v');
    return s.contains(RegExp(r'[",\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
  }

  return '${rows.map((row) => row.map(esc).join(',')).join('\n')}\n';
}

/// One row per plate.
String platesCsv(PlateStore store) {
  final rows = <List<Object?>>[
    [
      'plate_id',
      'date',
      'sample_id',
      'experiment',
      'condition',
      'time_h',
      'method',
      'dilution',
      'replicate',
      'volume_ml',
      'auto_count',
      'final_count',
      'added',
      'flags',
      'spreader',
      'tntc',
      'plate_cfu_per_ml',
      'plate_qualifier',
      'colour_mode',
      'class_0',
      'class_1',
      'spots',
      'notes',
      'image',
    ],
  ];
  for (final r in store.records) {
    final info = r.sampleId.isEmpty ? null : store.sampleInfo(r.sampleId);
    final est = r.estimateAlone(store.rule);
    final classes = r.classCounts;
    rows.add([
      r.id,
      r.createdAt.toIso8601String(),
      r.sampleId,
      info?.experiment,
      info?.condition,
      info?.timeH,
      r.isDropPlate ? 'drop' : 'spread',
      r.isDropPlate ? '' : '1e-${r.dilutionExp}',
      r.isDropPlate ? '' : r.replicate,
      r.volumeMl,
      r.autoCount,
      r.count,
      r.added,
      r.flags.join(';'),
      r.spreader,
      r.tntc,
      est.value,
      est.qualifier.name,
      r.colourMode.name,
      classes.isNotEmpty ? classes[0] : null,
      classes.length > 1 ? classes[1] : null,
      // e.g. "1e-5/r1:12; 1e-5/r2:9"
      [
        for (final s in r.spots)
          '1e-${s.dilutionExp}/r${s.replicate}:${countInSpot(s, r.colonies)}${s.tntc ? ' TNTC' : ''}',
      ].join('; '),
      r.notes,
      r.imagePath,
    ]);
  }
  return _csv(rows);
}

/// One row per sample: per-replicate CFU/mL summarised as mean ± SD and log₁₀.
String samplesCsv(PlateStore store) {
  final rows = <List<Object?>>[
    [
      'sample_id',
      'experiment',
      'condition',
      'time_h',
      'method',
      'rule',
      'plates',
      'replicates_used',
      'mean_cfu_per_ml',
      'sd_cfu_per_ml',
      'cv_percent',
      'log10_mean',
      'log10_sd',
      'estimated',
      'replicate_values',
      'notes',
    ],
  ];
  for (final info in store.allSamples()) {
    final plates = store.platesOf(info.sampleId);
    final res = info.analyse(plates, store.rule);
    final st = res.stats;
    rows.add([
      info.sampleId,
      info.experiment,
      info.condition,
      info.timeH,
      info.method.name,
      info.ruleFor(store.rule).label,
      plates.length,
      st.n,
      st.mean,
      st.sd,
      st.cvPercent,
      st.log10Mean,
      st.log10Sd,
      res.qualified,
      [
        for (final e in res.perReplicate.entries)
          'r${e.key}:${e.value.qualifier == Qualifier.exact ? '' : '${e.value.qualifier.name} '}${e.value.value}',
      ].join('; '),
      info.notes,
    ]);
  }
  return _csv(rows);
}

const _manifest = 'colony-counter-backup.json';

/// Everything (plates, sample plans, settings, photos) in one zip.
Future<Uint8List> buildBackup(PlateStore store) async {
  final archive = Archive();
  final manifest = {
    'format': 'colony-counter-backup',
    'version': 1,
    'created_at': DateTime.now().toIso8601String(),
    'settings': {'rule': store.rule.name, 'volume_ml': store.defaultVolumeMl},
    'samples': [for (final s in store.samplePlans) s.toJson()],
    'plates': [for (final r in store.records) r.toJson()],
  };
  final json = utf8.encode(jsonEncode(manifest));
  archive.addFile(ArchiveFile(_manifest, json.length, json));
  for (final r in store.records) {
    final bytes = await store.readPhoto(r);
    if (bytes == null) continue;
    // JPEGs are already compressed; store them as-is.
    archive.addFile(
      ArchiveFile.noCompress('photos/${r.imagePath}', bytes.length, bytes),
    );
  }
  archive.addFile(ArchiveFile('plates.csv', 0, utf8.encode(platesCsv(store))));
  archive.addFile(
    ArchiveFile('samples.csv', 0, utf8.encode(samplesCsv(store))),
  );
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

class RestoreSummary {
  RestoreSummary(this.platesAdded, this.platesSkipped, this.samplesAdded);

  final int platesAdded;
  final int platesSkipped;
  final int samplesAdded;
}

/// Merges a backup made by [buildBackup] into [store]; plates already present
/// (same ID) are kept as they are.
Future<RestoreSummary> restoreBackup(PlateStore store, Uint8List zip) async {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(zip);
  } catch (_) {
    throw const FormatException(
      'This file is not a Colony Counter backup (not a zip).',
    );
  }
  final manifestFile = archive.findFile(_manifest);
  if (manifestFile == null) {
    throw const FormatException('This zip is not a Colony Counter backup.');
  }
  final m = jsonDecode(
    utf8.decode(manifestFile.content as List<int>),
  ) as Map<String, dynamic>;
  final plates = [
    for (final p in m['plates'] as List? ?? const [])
      PlateRecord.fromJson(p as Map<String, dynamic>),
  ];
  final samples = [
    for (final s in m['samples'] as List? ?? const [])
      SampleInfo.fromJson(s as Map<String, dynamic>),
  ];
  final (added, skipped, samplesAdded) = await store.importAll(
    plates,
    samples,
    (name) async {
      final f = archive.findFile('photos/$name');
      return f == null ? null : Uint8List.fromList(f.content as List<int>);
    },
  );
  return RestoreSummary(added, skipped, samplesAdded);
}
