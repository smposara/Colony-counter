import 'dart:convert';

import 'csv_export.dart';
import 'export_source.dart';

Map<String, dynamic> exportMetadata(Map<String, dynamic> data) {
  final source = ExportSnapshot(data);
  final zonesOnly = data['zones_only'] == true;
  final backup = data['backup'] == true;
  final files = <String, String>{
    if (backup)
      'colony-counter-backup.json': jsonEncode({
        'format': 'colony-counter-backup',
        'version': 1,
        'created_at': data['created_at'],
        'settings': data['settings'],
        'samples': data['samples'],
        'plates': data['records'],
        'zone_plates': data['zones'],
        'zone_panels': data['panels'],
        'zone_calibrations': data['calibrations'],
      }),
    if (!zonesOnly || backup) ...{
      'plates.csv': platesCsv(source),
      'samples.csv': samplesCsv(source),
      'colonies.csv': coloniesCsv(source),
      'drops.csv': dropsCsv(source),
    },
    if (zonesOnly || (backup && source.zoneRecords.isNotEmpty)) ...{
      'zones.csv': zonesCsv(source),
      'zone_summary.csv': zoneSummaryCsv(source),
    },
  };
  return {
    'files': files,
    'photos': {
      for (final r in source.records) r.imagePath,
      for (final r in source.zoneRecords) r.imagePath,
    }.toList(),
  };
}
