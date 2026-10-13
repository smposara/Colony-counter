import '../core/calculator.dart';
import 'plate_record.dart';
import 'sample_info.dart';
import 'zone_calibration_record.dart';
import 'zone_record.dart';

/// Pure data interface, usable by export workers without Flutter or storage.
abstract interface class ExportSource {
  List<PlateRecord> get records;
  List<ZoneRecord> get zoneRecords;
  List<CalibrationProfile> get calibrations;
  CountingRule get rule;
  SampleInfo sampleInfo(String id);
  List<SampleInfo> allSamples();
  List<PlateRecord> platesOf(String id);
}

class ExportSnapshot implements ExportSource {
  ExportSnapshot(Map<String, dynamic> data)
    : records = [
        for (final r in data['records'] as List)
          PlateRecord.fromJson((r as Map).cast<String, dynamic>()),
      ],
      zoneRecords = [
        for (final r in data['zones'] as List)
          ZoneRecord.fromJson((r as Map).cast<String, dynamic>()),
      ],
      calibrations = [
        for (final r in data['calibrations'] as List)
          CalibrationProfile.fromJson((r as Map).cast<String, dynamic>()),
      ],
      rule = CountingRule.values.byName(data['rule'] as String) {
    for (final p in data['samples'] as List) {
      final s = SampleInfo.fromJson((p as Map).cast<String, dynamic>());
      _plans[s.sampleId] = s;
    }
    for (final r in records) {
      (_index[r.sampleId] ??= []).add(r);
    }
  }
  @override
  final List<PlateRecord> records;
  @override
  final List<ZoneRecord> zoneRecords;
  @override
  final List<CalibrationProfile> calibrations;
  @override
  final CountingRule rule;
  final _plans = <String, SampleInfo>{};
  final _index = <String, List<PlateRecord>>{};
  @override
  List<PlateRecord> platesOf(String id) => _index[id] ?? const [];
  @override
  SampleInfo sampleInfo(String id) =>
      _plans[id] ?? SampleInfo.inferred(id, platesOf(id));
  @override
  List<SampleInfo> allSamples() => [
    for (final id in {
      ..._plans.keys,
      ..._index.keys.where((id) => id.isNotEmpty),
    })
      sampleInfo(id),
  ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
}
