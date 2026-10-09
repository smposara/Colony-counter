import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/calculator.dart';
import '../core/plate.dart';
import 'plate_record.dart';
import 'sample_info.dart';
import 'zone_record.dart';
import 'storage/storage.dart';

/// Saved plates and settings, on top of a [StorageBackend] (files on phones,
/// IndexedDB in the browser).
class PlateStore extends ChangeNotifier {
  PlateStore(this.backend);

  final StorageBackend backend;
  final List<PlateRecord> _records = [];
  final Map<String, Uint8List> _photoCache = {};
  final Map<String, SampleInfo> _samples = {};
  final List<ZoneRecord> _zoneRecords = [];
  final List<ZonePanel> _zonePanels = [];
  CountingRule rule = CountingRule.fdaBam;
  double defaultVolumeMl = 0.1;

  /// Pre-filled in new samples.
  String defaultOperator = '';
  String defaultMedium = 'Nutrient Agar';

  /// Dish type for new samples and quick counts.
  PlateFormat defaultFormat = PlateFormat.dish90;

  /// Ask for a colony-by-colony check on every Nth plate (0 = never).
  int accuracyCheckEvery = 10;

  /// Interface language: 'system', 'en' or 'th'.
  String language = 'system';

  /// Colour theme: 'system', 'light' or 'dark'.
  String theme = 'system';

  /// The last zone plate's setup, offered for the next one.
  ZoneSetup zoneSetup = const ZoneSetup();

  /// The zone-measurement disclaimer has been accepted.
  bool zoneDisclaimerSeen = false;

  static const _recordsKey = 'plates';
  static const _settingsKey = 'settings';
  static const _samplesKey = 'samples';
  static const _zoneRecordsKey = 'zone_plates';
  static const _zonePanelsKey = 'zone_panels';
  static const _photoCacheSize = 24;

  static Future<PlateStore> open() async {
    final store = PlateStore(await openDefaultStorage());
    await store.load();
    return store;
  }

  List<PlateRecord> get records => List.unmodifiable(_records);

  /// Inhibition-zone plates, newest first.
  List<ZoneRecord> get zoneRecords => List.unmodifiable(_zoneRecords);

  /// Saved label panels for zone plates.
  List<ZonePanel> get zonePanels => List.unmodifiable(_zonePanels);

  Future<void> load() async {
    _records.clear();
    final recordsJson = await backend.readText(_recordsKey);
    if (recordsJson != null) {
      final list = jsonDecode(recordsJson) as List;
      _records.addAll(
        list.map((e) => PlateRecord.fromJson(e as Map<String, dynamic>)),
      );
      _records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    _samples.clear();
    final samplesJson = await backend.readText(_samplesKey);
    if (samplesJson != null) {
      for (final e in jsonDecode(samplesJson) as List) {
        final info = SampleInfo.fromJson(e as Map<String, dynamic>);
        _samples[info.sampleId] = info;
      }
    }
    _zoneRecords.clear();
    final zonesJson = await backend.readText(_zoneRecordsKey);
    if (zonesJson != null) {
      for (final e in jsonDecode(zonesJson) as List) {
        _zoneRecords.add(ZoneRecord.fromJson(e as Map<String, dynamic>));
      }
      _zoneRecords.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    _zonePanels.clear();
    final panelsJson = await backend.readText(_zonePanelsKey);
    if (panelsJson != null) {
      for (final e in jsonDecode(panelsJson) as List) {
        _zonePanels.add(ZonePanel.fromJson(e as Map<String, dynamic>));
      }
    }
    final settingsJson = await backend.readText(_settingsKey);
    if (settingsJson != null) {
      final s = jsonDecode(settingsJson) as Map<String, dynamic>;
      rule = CountingRule.spreadRules.firstWhere(
        (r) => r.name == s['rule'],
        orElse: () => CountingRule.fdaBam,
      );
      defaultVolumeMl = (s['volume_ml'] as num?)?.toDouble() ?? 0.1;
      defaultOperator = s['operator'] as String? ?? '';
      defaultMedium = s['medium'] as String? ?? 'Nutrient Agar';
      defaultFormat = PlateFormat.byName(s['format'] as String?);
      accuracyCheckEvery = (s['accuracy_every'] as num?)?.toInt() ?? 10;
      language = s['language'] as String? ?? 'system';
      theme = s['theme'] as String? ?? 'system';
      final zs = s['zone_setup'];
      zoneSetup = zs is Map<String, dynamic>
          ? ZoneSetup.fromJson(zs)
          : const ZoneSetup();
      zoneDisclaimerSeen = s['zone_disclaimer_seen'] as bool? ?? false;
    }
    notifyListeners();
  }

  /// Stores the photo for a new plate and returns its stored name.
  Future<String> savePhoto(Uint8List bytes, String id) async {
    final name = '$id.jpg';
    await backend.writePhoto(name, bytes);
    _cachePhoto(name, bytes);
    return name;
  }

  Future<Uint8List?> readPhoto(PlateRecord r) => readPhotoPath(r.imagePath);

  /// A stored photo by name (colony and zone plates share the photo folder).
  Future<Uint8List?> readPhotoPath(String name) async {
    final cached = _photoCache[name];
    if (cached != null) return cached;
    final bytes = await backend.readPhoto(name);
    if (bytes != null) _cachePhoto(name, bytes);
    return bytes;
  }

  void _cachePhoto(String name, Uint8List bytes) {
    _photoCache.remove(name);
    _photoCache[name] = bytes;
    while (_photoCache.length > _photoCacheSize) {
      _photoCache.remove(_photoCache.keys.first);
    }
  }

  Future<void> upsert(PlateRecord record) async {
    _records.removeWhere((r) => r.id == record.id);
    _records.add(record);
    _records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await _save();
  }

  Future<void> delete(PlateRecord record) async {
    _records.removeWhere((r) => r.id == record.id);
    _photoCache.remove(record.imagePath);
    await backend.deletePhoto(record.imagePath);
    await _save();
  }

  Future<void> upsertZone(ZoneRecord record) async {
    _zoneRecords.removeWhere((r) => r.id == record.id);
    _zoneRecords.add(record);
    _zoneRecords.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await _saveZones();
  }

  Future<void> deleteZone(ZoneRecord record) async {
    _zoneRecords.removeWhere((r) => r.id == record.id);
    _photoCache.remove(record.imagePath);
    await backend.deletePhoto(record.imagePath);
    await _saveZones();
  }

  /// Adds or replaces the panel called [panel]'s name.
  Future<void> savePanel(ZonePanel panel) async {
    final i = _zonePanels.indexWhere((p) => p.name == panel.name);
    if (i < 0) {
      _zonePanels.add(panel);
    } else {
      _zonePanels[i] = panel;
    }
    await _savePanels();
  }

  Future<void> deletePanel(String name) async {
    _zonePanels.removeWhere((p) => p.name == name);
    await _savePanels();
  }

  /// Experiments and organisms used on zone plates, for suggestions.
  List<String> zoneExperiments() => {
    for (final r in _zoneRecords)
      if (r.experiment.isNotEmpty) r.experiment,
  }.toList()..sort();
  List<String> zoneOrganisms() => {
    for (final r in _zoneRecords)
      if (r.organism.isNotEmpty) r.organism,
  }.toList()..sort();

  Future<void> setRule(CountingRule r) async {
    rule = r;
    await _saveSettings();
  }

  Future<void> setDefaultVolume(double v) async {
    defaultVolumeMl = v;
    await _saveSettings();
  }

  Future<void> setDefaults({
    String? operator,
    String? medium,
    PlateFormat? format,
    int? accuracyCheckEvery,
    String? language,
    String? theme,
  }) async {
    this.language = language ?? this.language;
    this.theme = theme ?? this.theme;
    defaultOperator = operator ?? defaultOperator;
    defaultMedium = medium ?? defaultMedium;
    defaultFormat = format ?? defaultFormat;
    this.accuracyCheckEvery = accuracyCheckEvery ?? this.accuracyCheckEvery;
    await _saveSettings();
  }

  Future<void> acceptZoneDisclaimer() async {
    zoneDisclaimerSeen = true;
    await _saveSettings();
  }

  Future<void> setZoneSetup(ZoneSetup setup) async {
    zoneSetup = setup;
    await _saveSettings();
  }

  /// Plates grouped by sample ID.
  Map<String, List<PlateRecord>> samples() {
    final out = <String, List<PlateRecord>>{};
    for (final r in _records) {
      if (r.sampleId.isNotEmpty) (out[r.sampleId] ??= []).add(r);
    }
    return out;
  }

  List<PlateRecord> platesOf(String sampleId) => [
    for (final r in _records)
      if (r.sampleId == sampleId) r,
  ];

  /// Every known sample: those set up in advance and those with plates,
  /// newest first.
  List<SampleInfo> allSamples() {
    final grouped = samples();
    final ids = {..._samples.keys, ...grouped.keys};
    final list = [for (final id in ids) sampleInfo(id)];
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  /// The saved plan for [id], or one inferred from its plates.
  SampleInfo sampleInfo(String id) =>
      _samples[id] ?? SampleInfo.inferred(id, platesOf(id));

  bool hasPlan(String id) => _samples.containsKey(id);

  List<String> experiments() {
    final names = {
      for (final s in allSamples())
        if (s.experiment.isNotEmpty) s.experiment,
    }.toList();
    names.sort();
    return names;
  }

  Future<void> upsertSample(SampleInfo info, {String? previousId}) async {
    if (previousId != null && previousId != info.sampleId) {
      _samples.remove(previousId);
      // Move the plates to the new ID.
      for (var i = 0; i < _records.length; i++) {
        if (_records[i].sampleId == previousId) {
          _records[i] = _records[i].copyWith(sampleId: info.sampleId);
        }
      }
      await _save();
    }
    _samples[info.sampleId] = info;
    await _saveSamples();
  }

  /// Removes the sample plan; with [withPlates] also deletes its plates.
  Future<void> deleteSample(String id, {bool withPlates = false}) async {
    _samples.remove(id);
    if (withPlates) {
      for (final r in platesOf(id)) {
        _photoCache.remove(r.imagePath);
        await backend.deletePhoto(r.imagePath);
      }
      _records.removeWhere((r) => r.sampleId == id);
      await _save();
    }
    await _saveSamples();
  }

  /// Adds plates, samples and photos from a backup. Items whose ID already
  /// exists here are skipped. Returns (plates added, plates skipped, samples added).
  Future<(int, int, int)> importAll(
    List<PlateRecord> plates,
    List<SampleInfo> sampleInfos,
    Future<Uint8List?> Function(String imagePath) photo, {
    List<ZoneRecord> zonePlates = const [],
    List<ZonePanel> zonePanels = const [],
  }) async {
    final have = {for (final r in _records) r.id};
    final usedNames = {
      for (final r in _records) r.imagePath,
      for (final r in _zoneRecords) r.imagePath,
    };
    // A free, safe photo name for a restored plate (see below).
    String freeName(String name, String id) {
      var safe = safePhotoName(name, id);
      if (usedNames.contains(safe)) {
        final stem = safe.endsWith('.jpg')
            ? safe.substring(0, safe.length - 4)
            : safe;
        var n = 2;
        while (usedNames.contains('${stem}_$n.jpg')) {
          n++;
        }
        safe = '${stem}_$n.jpg';
      }
      usedNames.add(safe);
      return safe;
    }

    var added = 0, skipped = 0, samplesAdded = 0;
    for (final r in plates) {
      // A backup can list the same plate twice (e.g. merged exports).
      if (!have.add(r.id)) {
        skipped++;
        continue;
      }
      final bytes = await photo(r.imagePath);
      // The name comes from the backup file: never let it leave the photo
      // folder (e.g. "../settings.json"), and never overwrite another
      // plate's photo.
      final safe = freeName(r.imagePath, r.id);
      _photoCache.remove(safe);
      if (bytes != null) await backend.writePhoto(safe, bytes);
      _records.add(
        safe == r.imagePath
            ? r
            : PlateRecord.fromJson({...r.toJson(), 'image': safe}),
      );
      added++;
    }
    for (final info in sampleInfos) {
      if (!_samples.containsKey(info.sampleId)) {
        _samples[info.sampleId] = info;
        samplesAdded++;
      }
    }
    // Zone plates: the same rules (skip known IDs, safe and free photo names).
    final haveZones = {for (final r in _zoneRecords) r.id};
    var zonesAdded = 0;
    for (final r in zonePlates) {
      if (!haveZones.add(r.id)) {
        skipped++;
        continue;
      }
      final bytes = await photo(r.imagePath);
      final safe = freeName(r.imagePath, r.id);
      _photoCache.remove(safe);
      if (bytes != null) await backend.writePhoto(safe, bytes);
      _zoneRecords.add(
        safe == r.imagePath
            ? r
            : ZoneRecord.fromJson({...r.toJson(), 'image': safe}),
      );
      zonesAdded++;
    }
    for (final p in zonePanels) {
      if (!_zonePanels.any((q) => q.name == p.name)) _zonePanels.add(p);
    }
    _records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _zoneRecords.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await _save();
    await _saveSamples();
    if (zonePlates.isNotEmpty || zonePanels.isNotEmpty) {
      await _saveZones();
      await _savePanels();
    }
    return (added + zonesAdded, skipped, samplesAdded);
  }

  List<SampleInfo> get samplePlans => List.unmodifiable(_samples.values);

  Future<void> _saveSamples() async {
    await backend.writeText(
      _samplesKey,
      jsonEncode([for (final s in _samples.values) s.toJson()]),
    );
    notifyListeners();
  }

  Future<void> _save() async {
    await backend.writeText(
      _recordsKey,
      jsonEncode([for (final r in _records) r.toJson()]),
    );
    notifyListeners();
  }

  Future<void> _saveZones() async {
    await backend.writeText(
      _zoneRecordsKey,
      jsonEncode([for (final r in _zoneRecords) r.toJson()]),
    );
    notifyListeners();
  }

  Future<void> _savePanels() async {
    await backend.writeText(
      _zonePanelsKey,
      jsonEncode([for (final p in _zonePanels) p.toJson()]),
    );
    notifyListeners();
  }

  Future<void> _saveSettings() async {
    await backend.writeText(
      _settingsKey,
      jsonEncode({
        'rule': rule.name,
        'volume_ml': defaultVolumeMl,
        'operator': defaultOperator,
        'medium': defaultMedium,
        'format': defaultFormat.name,
        'accuracy_every': accuracyCheckEvery,
        'language': language,
        'theme': theme,
        'zone_setup': zoneSetup.toJson(),
        'zone_disclaimer_seen': zoneDisclaimerSeen,
      }),
    );
    notifyListeners();
  }
}

/// [name] if it is a plain file name, otherwise a safe name made from [id].
String safePhotoName(String name, String id) {
  final plain = RegExp(r'^[A-Za-z0-9_-][A-Za-z0-9._-]*$');
  if (plain.hasMatch(name) && !name.contains('..')) return name;
  final cleaned = id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  return 'restored_${cleaned.isEmpty ? 'photo' : cleaned}.jpg';
}
