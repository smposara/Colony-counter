import 'package:flutter/foundation.dart';

import '../core/worker/client.dart';
import 'examples.dart';
import 'export_metadata.dart';
import 'plate_store.dart';

Future<Map<String, dynamic>> prepareExport(
  PlateStore store, {
  bool backup = false,
  bool zonesOnly = false,
  bool includeExamples = false,
}) async {
  // Capture immutable records/preferences together, then yield between batches
  // while converting records to portable messages on the UI side. The
  // built-in examples stay out of CSVs and backups (only the generator that
  // packs them includes them).
  final records = [
    for (final r in store.records)
      if (includeExamples || !r.isExample) r,
  ];
  final zones = [
    for (final r in store.zoneRecords)
      if (includeExamples || !r.isExample) r,
  ];
  final data = <String, dynamic>{
    'kind': 'export',
    'backup': backup,
    'zones_only': zonesOnly,
    'created_at': DateTime.now().toIso8601String(),
    'rule': store.rule.name,
    'settings': {
      'rule': store.rule.name,
      'volume_ml': store.defaultVolumeMl,
      'operator': store.defaultOperator,
      'medium': store.defaultMedium,
      'format': store.defaultFormat.name,
      'accuracy_every': store.accuracyCheckEvery,
      'language': store.language,
      'theme': store.theme,
      'zone_setup': store.zoneSetup.toJson(),
      'zone_disclaimer_seen': store.zoneDisclaimerSeen,
    },
    'samples': [
      for (final s in store.samplePlans)
        if (includeExamples || !isExampleSample(store, s)) s.toJson(),
    ],
    'calibrations': [for (final s in store.calibrations) s.toJson()],
    'panels': [for (final s in store.zonePanels) s.toJson()],
  };
  final plates = <Map<String, dynamic>>[];
  for (var i = 0; i < records.length; i++) {
    plates.add(records[i].toJson());
    if (i % 16 == 15) await Future<void>.delayed(Duration.zero);
  }
  data['records'] = plates;
  final zoneData = <Map<String, dynamic>>[];
  for (var i = 0; i < zones.length; i++) {
    zoneData.add(zones[i].toJson());
    if (i % 16 == 15) await Future<void>.delayed(Duration.zero);
  }
  data['zones'] = zoneData;
  if (kIsWeb) return runPhotoJob(Uint8List(0), data);
  return compute(exportMetadata, data);
}
