import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../core/calculator.dart';
import '../core/plate.dart';
import 'plate_record.dart';
import 'plate_store.dart';
import 'export_jobs.dart';
import 'export_source.dart';
import 'streaming_zip.dart';
export 'csv_export.dart';
import 'sample_info.dart';
import 'zone_calibration_record.dart';
import 'zone_record.dart';

const _manifest = 'colony-counter-backup.json';

/// Incremental ZIP output. Photos are loaded one at a time, bypassing the UI
/// photo cache. The interactive backup action consumes this stream directly.
/// The built-in examples are left out unless [includeExamples].
Stream<Uint8List> buildBackupStream(
  PlateStore store, {
  bool includeExamples = false,
}) => store.readSnapshot(() => _backupStream(store, includeExamples));

Stream<Uint8List> _backupStream(PlateStore store, bool examples) async* {
  final metadata = await prepareExport(
    store,
    backup: true,
    includeExamples: examples,
  );
  final files = (metadata['files'] as Map).cast<String, String>();
  final photos = (metadata['photos'] as List).cast<String>();
  final entries = <ZipEntrySource>[
    for (final e in files.entries)
      ZipEntrySource(
        e.key,
        () async => Uint8List.fromList(utf8.encode(e.value)),
      ),
    for (final name in photos)
      ZipEntrySource('photos/$name', () => store.backend.readPhoto(name)),
  ];
  yield* streamZip(Stream.fromIterable(entries));
}

/// Compatibility API for tests/small callers that explicitly need byte data.
/// Production sharing uses [buildBackupStream], never this whole-file buffer.
Future<Uint8List> buildBackup(
  PlateStore store, {
  bool includeExamples = false,
}) async {
  final result = BytesBuilder(copy: false);
  await for (final chunk in buildBackupStream(
    store,
    includeExamples: includeExamples,
  )) {
    result.add(chunk);
  }
  return result.takeBytes();
}

class RestoreSummary {
  RestoreSummary(this.platesAdded, this.platesSkipped, this.samplesAdded);

  final int platesAdded;
  final int platesSkipped;
  final int samplesAdded;
}

/// Merges a backup made by [buildBackup] into [store]; plates already present
/// (same ID) are kept as they are. With [onlyIntoEmpty], nothing is added
/// unless the store holds no plates, samples or zone plates at that moment.
Future<RestoreSummary> restoreBackup(
  PlateStore store,
  Uint8List zip, {
  bool onlyIntoEmpty = false,
}) async {
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
  // The built-in examples do not count: a new phone has them.
  final wasEmpty =
      store.records.every((r) => isExamplePlate(store, r)) &&
      store.zoneRecords.every((r) => r.isExample);
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
    onlyIntoEmpty: onlyIntoEmpty,
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
    language: const ['system', 'en', 'th'].contains(s['language'])
        ? s['language'] as String
        : null,
    theme: const ['system', 'light', 'dark'].contains(s['theme'])
        ? s['theme'] as String
        : null,
    zoneSetup: s['zone_setup'] is Map<String, dynamic>
        ? ZoneSetup.fromJson(s['zone_setup'] as Map<String, dynamic>)
        : null,
    zoneDisclaimerSeen: s['zone_disclaimer_seen'] is bool
        ? s['zone_disclaimer_seen'] as bool
        : null,
  );
}
