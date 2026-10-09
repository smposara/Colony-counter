import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../core/calculator.dart';
import '../core/drop_stats.dart';
import '../core/petrifilm.dart';
import '../core/plate.dart';
import '../core/spots.dart';
import 'drop_results.dart';
import 'plate_record.dart';
import 'plate_store.dart';
import 'sample_info.dart';
import 'zone_calibration_record.dart';
import 'zone_record.dart';

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
      'median_diameter_mm',
      'plate_type',
      'checked_by_hand',
      'auto_removed',
      'incubation_h',
      'timelapse_series',
      'spots',
      'notes',
      'image',
      'film_type',
      'film_counts',
      'film_estimates',
      'film_squares',
      'film_gas',
      'film_squares_left_out',
      'drop_layout',
      'drop_mode',
      'drop_window',
      'drops_planned',
      'drops_found',
      'drops_excluded',
      'drop_flags',
    ],
  ];
  String pairs(Map<String, num> m) =>
      [for (final e in m.entries) '${e.key}=${e.value}'].join(';');
  for (final r in store.records) {
    final info = r.sampleId.isEmpty ? null : store.sampleInfo(r.sampleId);
    final est = r.estimateAlone(
      store.rule,
      membraneRule: info?.membraneRule ?? CountingRule.membrane80,
      dropMode: info?.dropMode ?? DropMode.pooled,
      dropWindow: info?.dropWindow ?? kDropWindow,
    );
    final classes = r.classCounts;
    rows.add([
      r.id,
      r.createdAt.toIso8601String(),
      r.sampleId,
      info?.experiment,
      info?.condition,
      info?.timeH,
      r.isDropPlate
          ? 'drop'
          : r.format.membrane
          ? 'membrane'
          : r.isFilm
          ? 'film'
          : 'spread',
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
      medianDiameterMm(r),
      r.format.name,
      r.verified,
      r.rejected.fold<int>(0, (s, c) => s + c.n),
      r.incubationH,
      r.seriesId,
      // e.g. "1e-5/r1:12; 1e-5/r2:9"
      [
        for (final s in r.spots)
          '1e-${s.dilutionExp}/r${s.replicate}:${countInSpot(s, r.colonies)}${s.tntc ? ' TNTC' : ''}${s.isExcluded ? ' excluded (${s.excluded!.name})' : ''}',
      ].join('; '),
      r.notes,
      r.imagePath,
      r.filmType,
      if (r.isFilm)
        ...() {
          final t = r.filmTally;
          return [
            pairs(t.counts),
            t.estimates == null
                ? ''
                : pairs({
                    for (final e in t.estimates!.entries)
                      e.key: e.value.round(),
                  }),
            t.estimates == null ? '' : t.squaresUsed,
            // e.g. "blue_gas=12;blue_no_gas=8;red_gas=16;red_no_gas=4"
            filmUsesGas(r.filmType!)
                ? [
                    for (final MapEntry(key: k, value: (g, n)) in gasSplit(
                      r.filmType!,
                      filmColoniesOf(r.filmType!, r.colonies),
                    ).entries)
                      '${k}_gas=$g;${k}_no_gas=$n',
                  ].join(';')
                : '',
            r.excludedSquares.length,
          ];
        }()
      else ...[
        '',
        '',
        '',
        '',
        '',
      ],
      ..._dropPlateColumns(r, info),
    ]);
  }
  return _csv(rows);
}

/// Drop layout, calculation and drop counts of a drop plate; blanks otherwise.
List<Object?> _dropPlateColumns(PlateRecord r, SampleInfo? info) {
  if (!r.isDropPlate) return List.filled(7, '');
  final drop = info != null && info.isDrop ? info : null;
  final w = drop?.dropWindow ?? kDropWindow;
  return [
    drop?.dropArrangement.name ?? '',
    (drop?.dropMode ?? DropMode.pooled).name,
    '${w.$1}-${w.$2}',
    drop?.dropsPerPlate ?? '',
    r.spots.length,
    r.spots.where((s) => s.isExcluded).length,
    {for (final s in r.spots) ...s.flags}.join(';'),
  ];
}

/// One row per sample: per-replicate CFU/mL summarised as mean ± SD and log₁₀.
String samplesCsv(PlateStore store) {
  final rows = <List<Object?>>[
    [
      'sample_id',
      'experiment',
      'condition',
      'time_h',
      'strain',
      'medium',
      'medium_batch',
      'incubation_temp_c',
      'incubation_h',
      'operator',
      'tags',
      'method',
      'plate_type',
      'rule',
      'plates',
      'replicates_used',
      'mean_cfu_per_ml',
      'sd_cfu_per_ml',
      'cv_percent',
      'log10_mean',
      'log10_sd',
      'unit',
      'mean_in_unit',
      'sd_in_unit',
      'log10_mean_in_unit',
      'sample_g',
      'diluent_ml',
      'estimated',
      'replicate_values',
      'notes',
      'result',
      'drop_mode',
      'drop_window',
      'drop_cfu_per_ml',
      'drop_qualifier',
      'drop_dilution_used',
      'drop_mean',
      'drop_sd',
      'drop_vmr',
      'drop_chi2_p',
      'cfu_ci_low',
      'cfu_ci_high',
      'drop_warnings',
    ],
  ];
  for (final info in store.allSamples()) {
    final plates = store.platesOf(info.sampleId);
    // A dry film gives one row per result (e.g. E. coli and coliforms).
    for (final result
        in info.filmResults.isEmpty
            ? const <String?>[null]
            : info.filmResults) {
      final res = info.analyse(plates, store.rule, result: result);
      final st = res.stats;
      rows.add([
        info.sampleId,
        info.experiment,
        info.condition,
        info.timeH,
        info.strain,
        info.medium,
        info.mediumBatch,
        info.incubationTempC,
        info.incubationH,
        info.operator,
        info.tags.join('; '),
        info.method.name,
        info.format.name,
        // Drop samples: their own window and calculation.
        info.isDrop
            ? 'Drop ${info.dropWindow.$1}–${info.dropWindow.$2} ${info.dropMode.name}'
            : info.ruleFor(store.rule).label,
        plates.length,
        st.n,
        st.mean,
        st.sd,
        st.cvPercent,
        st.log10Mean,
        st.log10Sd,
        info.unitLabel,
        st.n > 0 ? st.mean * info.unitFactor : null,
        st.n > 1 ? st.sd * info.unitFactor : null,
        st.n > 0 ? st.log10Mean + math.log(info.unitFactor) / math.ln10 : null,
        info.isSolid ? info.sampleWeightG : null,
        info.isSolid ? info.diluentMl : null,
        res.qualified,
        [
          for (final e in res.perReplicate.entries)
            'r${e.key}:${e.value.qualifier == Qualifier.exact ? '' : '${e.value.qualifier.name} '}${e.value.value}',
        ].join('; '),
        info.notes,
        result,
        ..._dropSampleColumns(info, plates),
      ]);
    }
  }
  return _csv(rows);
}

/// The sample's drop table over all its drops: CFU/mL with its 95 %
/// interval (CFU/mL), and the first dilution used's mean, SD, VMR and χ²
/// p-value; blanks for other methods.
List<Object?> _dropSampleColumns(SampleInfo info, List<PlateRecord> plates) {
  if (!info.isDrop) return List.filled(12, '');
  final d = dropSummary(info, plates);
  final e = d.estimate;
  final used = e.dilutionsUsed.isEmpty
      ? null
      : d.rows.firstWhere((r) => r.dilutionExp == e.dilutionsUsed.first);
  return [
    d.mode.name,
    '${d.window.$1}-${d.window.$2}',
    e.cfuPerMl,
    e.qualifier,
    [for (final x in e.dilutionsUsed) '1e-$x'].join(';'),
    used?.mean,
    used != null && used.counts.length > 1 ? used.sd : null,
    used != null && used.counts.length > 1 ? used.vmr : null,
    used != null && used.counts.length > 1 ? used.p : null,
    e.low,
    e.high,
    d.warnings.join(';'),
  ];
}

/// One row per drop of every drop plate: label, count and position.
String dropsCsv(PlateStore store) {
  double r2(double v) => (v * 100).round() / 100;
  final rows = <List<Object?>>[
    [
      'plate_id',
      'sample_id',
      'drop',
      'position',
      'dilution',
      'replicate',
      'count',
      'tntc',
      'excluded',
      'exclusion_reason',
      'flags',
      'x_mm',
      'y_mm',
      'diameter_mm',
    ],
  ];
  for (final r in store.records) {
    final mm = r.plate.mmPerPx;
    for (var i = 0; i < r.spots.length; i++) {
      final s = r.spots[i];
      rows.add([
        r.id,
        r.sampleId,
        i + 1,
        s.position,
        '1e-${s.dilutionExp}',
        s.replicate,
        countInSpot(s, r.colonies),
        s.tntc,
        s.isExcluded,
        s.excluded?.name ?? '',
        s.flags.join(';'),
        r2((s.cx - r.plate.cx) * mm),
        r2((s.cy - r.plate.cy) * mm),
        r2(2 * s.radius * mm),
      ]);
    }
  }
  return _csv(rows);
}

/// Median diameter (mm) of single colonies (clusters excluded), or null.
double? medianDiameterMm(PlateRecord r) {
  final d = [
    for (final c in r.colonies)
      if (c.n == 1 && !c.manual) 2 * c.radiusPx * r.plate.mmPerPx,
  ]..sort();
  if (d.isEmpty) return null;
  final m = d.length.isOdd
      ? d[d.length ~/ 2]
      : (d[d.length ~/ 2 - 1] + d[d.length ~/ 2]) / 2;
  return (m * 100).round() / 100;
}

/// One row per colony mark, for size distributions and spatial analyses.
///
/// Positions are in mm from the plate centre (x right, y down), so they
/// compare across photos. Diameters of hand-added marks are nominal.
String coloniesCsv(PlateStore store) {
  double r3(double v) => (v * 1000).round() / 1000;
  final rows = <List<Object?>>[
    [
      'plate_id',
      'sample_id',
      'dilution',
      'replicate',
      'colony',
      'x_mm',
      'y_mm',
      'diameter_mm',
      'colonies_in_mark',
      'added_by_hand',
      'colour_class',
      'colour_class_name',
      'lab_l',
      'lab_a',
      'lab_b',
      'drop',
      'drop_dilution',
      'drop_replicate',
      'gas',
      'yellow_zone',
    ],
  ];
  for (final r in store.records) {
    final mm = r.plate.mmPerPx;
    for (var i = 0; i < r.colonies.length; i++) {
      final c = r.colonies[i];
      final drop = r.spots.indexWhere((s) => s.contains(c.x, c.y));
      final names = r.isFilm ? filmKinds(r.filmType!) : r.colourMode.classNames;
      rows.add([
        r.id,
        r.sampleId,
        r.isDropPlate ? '' : '1e-${r.dilutionExp}',
        r.isDropPlate ? '' : r.replicate,
        i + 1,
        r3((c.x - r.plate.cx) * mm),
        r3((c.y - r.plate.cy) * mm),
        r3(2 * c.radiusPx * mm),
        c.n,
        c.manual,
        c.cls,
        names[c.cls.clamp(0, names.length - 1)],
        c.colour?.l,
        c.colour?.a,
        c.colour?.b,
        drop < 0 ? '' : drop + 1,
        drop < 0 ? '' : '1e-${r.spots[drop].dilutionExp}',
        drop < 0 ? '' : r.spots[drop].replicate,
        r.isFilm ? c.gas : '',
        r.isFilm ? c.yellow : '',
      ]);
    }
  }
  return _csv(rows);
}

/// One row per inhibition zone (disk or well) on the zone plates.
///
/// diameter_mm is to 0.1 mm as stored; diameter_mm_rounded is the whole mm
/// shown on screen (EUCAST reads to the nearest mm). "No zone" is reported
/// as the disk (or well) size. Positions are in mm from the plate centre.
/// Measurement only: no S/I/R interpretation.
String zonesCsv(PlateStore store) {
  double r1(double v) => (v * 10).round() / 10;
  double r3(double v) => (v * 1000).round() / 1000;
  final rows = <List<Object?>>[
    [
      'plate_id',
      'date',
      'experiment',
      'organism',
      'assay',
      'disk_or_well_mm',
      'zone',
      'label',
      'replicate',
      'diameter_mm',
      'diameter_mm_rounded',
      'no_zone',
      'auto_diameter_mm',
      'edited',
      'added_by_hand',
      'confidence',
      'flags',
      'x_mm',
      'y_mm',
      'image',
    ],
  ];
  for (final r in store.zoneRecords.reversed) {
    for (var i = 0; i < r.marks.length; i++) {
      final m = r.marks[i];
      final v = m.reportedMm(r.diskMm);
      rows.add([
        r.id,
        r.createdAt.toIso8601String().substring(0, 10),
        r.experiment,
        r.organism,
        r.assay.name,
        r.diskMm,
        i + 1,
        m.label,
        r.replicate,
        v.isFinite ? r1(v) : null,
        m.roundedMm(r.diskMm),
        m.noZone,
        m.autoDiameterMm.isFinite ? r1(m.autoDiameterMm) : null,
        m.edited,
        m.manual,
        (m.confidence * 100).round() / 100,
        m.flags.join(' '),
        r3((m.x - r.plate.cx) * r.mmPerPx),
        r3((m.y - r.plate.cy) * r.mmPerPx),
        r.imagePath,
      ]);
    }
  }
  return _csv(rows);
}

/// Mean ± SD zone diameter per experiment, organism and label (replicate
/// plates pooled; unlabelled and unmeasured zones left out).
String zoneSummaryCsv(PlateStore store) {
  double? r2(double v) => v.isFinite ? (v * 100).round() / 100 : null;
  return _csv([
    ['experiment', 'organism', 'label', 'n', 'mean_mm', 'sd_mm'],
    for (final z in summariseZones(store.zoneRecords))
      [z.experiment, z.organism, z.label, z.n, r2(z.mean), r2(z.sd)],
  ]);
}

const _manifest = 'colony-counter-backup.json';

/// Everything (plates, sample plans, settings, photos) in one zip.
Future<Uint8List> buildBackup(PlateStore store) async {
  final archive = Archive();
  final manifest = {
    'format': 'colony-counter-backup',
    'version': 1,
    'created_at': DateTime.now().toIso8601String(),
    'settings': {
      'rule': store.rule.name,
      'volume_ml': store.defaultVolumeMl,
      'operator': store.defaultOperator,
      'medium': store.defaultMedium,
      'format': store.defaultFormat.name,
      'accuracy_every': store.accuracyCheckEvery,
    },
    'samples': [for (final s in store.samplePlans) s.toJson()],
    'plates': [for (final r in store.records) r.toJson()],
    // Inhibition-zone plates and label panels (older versions ignore them).
    'zone_plates': [for (final r in store.zoneRecords) r.toJson()],
    'zone_panels': [for (final p in store.zonePanels) p.toJson()],
    'zone_calibrations': [for (final p in store.calibrations) p.toJson()],
  };
  final json = utf8.encode(jsonEncode(manifest));
  archive.addFile(ArchiveFile(_manifest, json.length, json));
  for (final name in [
    for (final r in store.records) r.imagePath,
    for (final r in store.zoneRecords) r.imagePath,
  ]) {
    final bytes = await store.readPhotoPath(name);
    if (bytes == null) continue;
    // JPEGs are already compressed; store them as-is.
    archive.addFile(
      ArchiveFile.noCompress('photos/$name', bytes.length, bytes),
    );
  }
  for (final (name, csv) in [
    ('plates.csv', platesCsv(store)),
    ('samples.csv', samplesCsv(store)),
    ('colonies.csv', coloniesCsv(store)),
    ('drops.csv', dropsCsv(store)),
    if (store.zoneRecords.isNotEmpty) ...[
      ('zones.csv', zonesCsv(store)),
      ('zone_summary.csv', zoneSummaryCsv(store)),
    ],
  ]) {
    final bytes = utf8.encode(csv);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }
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
  final zonePlates = [
    for (final z in m['zone_plates'] as List? ?? const [])
      ZoneRecord.fromJson(z as Map<String, dynamic>),
  ];
  final zonePanels = [
    for (final p in m['zone_panels'] as List? ?? const [])
      ZonePanel.fromJson(p as Map<String, dynamic>),
  ];
  // On a device with no plates yet (e.g. a new phone) the backup's settings
  // come back too; otherwise keep the settings already chosen here.
  final calibrations = [
    for (final c in m['zone_calibrations'] as List? ?? const [])
      CalibrationProfile.fromJson(c as Map<String, dynamic>),
  ];
  final wasEmpty = store.records.isEmpty && store.zoneRecords.isEmpty;
  final (added, skipped, samplesAdded) = await store.importAll(
    plates,
    samples,
    (name) async {
      final f = archive.findFile('photos/$name');
      return f == null ? null : Uint8List.fromList(f.content as List<int>);
    },
    zonePlates: zonePlates,
    zonePanels: zonePanels,
    calibrations: calibrations,
  );
  final settings = m['settings'];
  if (wasEmpty && settings is Map<String, dynamic>) {
    await _restoreSettings(store, settings);
  }
  return RestoreSummary(added, skipped, samplesAdded);
}

Future<void> _restoreSettings(PlateStore store, Map<String, dynamic> s) async {
  T? byName<T extends Enum>(List<T> values, Object? name) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return null;
  }

  final rule = byName(CountingRule.values, s['rule']);
  if (rule != null) await store.setRule(rule);
  final volume = s['volume_ml'];
  if (volume is num && volume > 0) {
    await store.setDefaultVolume(volume.toDouble());
  }
  final every = s['accuracy_every'];
  await store.setDefaults(
    operator: s['operator'] is String ? s['operator'] as String : null,
    medium: s['medium'] is String ? s['medium'] as String : null,
    format: byName(PlateFormat.values, s['format']),
    accuracyCheckEvery: every is int && every >= 0 ? every : null,
  );
}
