import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/calculator.dart';
import '../core/plate.dart';
import 'plate_record.dart';
import 'sample_info.dart';
import 'storage/storage.dart';

/// Saved plates and settings, on top of a [StorageBackend] (files on phones,
/// IndexedDB in the browser).
class PlateStore extends ChangeNotifier {
  PlateStore(this.backend);

  final StorageBackend backend;
  final List<PlateRecord> _records = [];
  final Map<String, Uint8List> _photoCache = {};
  final Map<String, SampleInfo> _samples = {};
  CountingRule rule = CountingRule.fdaBam;
  double defaultVolumeMl = 0.1;

  /// Pre-filled in new samples.
  String defaultOperator = '';
  String defaultMedium = 'Nutrient Agar';

  /// Dish type for new samples and quick counts.
  PlateFormat defaultFormat = PlateFormat.dish90;

  /// Ask for a colony-by-colony check on every Nth plate (0 = never).
  int accuracyCheckEvery = 10;

  static const _recordsKey = 'plates';
  static const _settingsKey = 'settings';
  static const _samplesKey = 'samples';
  static const _photoCacheSize = 24;

  static Future<PlateStore> open() async {
    final store = PlateStore(await openDefaultStorage());
    await store.load();
    return store;
  }

  List<PlateRecord> get records => List.unmodifiable(_records);

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

  Future<Uint8List?> readPhoto(PlateRecord r) async {
    final cached = _photoCache[r.imagePath];
    if (cached != null) return cached;
    final bytes = await backend.readPhoto(r.imagePath);
    if (bytes != null) _cachePhoto(r.imagePath, bytes);
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
  }) async {
    defaultOperator = operator ?? defaultOperator;
    defaultMedium = medium ?? defaultMedium;
    defaultFormat = format ?? defaultFormat;
    this.accuracyCheckEvery = accuracyCheckEvery ?? this.accuracyCheckEvery;
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
    Future<Uint8List?> Function(String imagePath) photo,
  ) async {
    final have = {for (final r in _records) r.id};
    var added = 0, skipped = 0, samplesAdded = 0;
    for (final r in plates) {
      if (have.contains(r.id)) {
        skipped++;
        continue;
      }
      final bytes = await photo(r.imagePath);
      if (bytes != null) await backend.writePhoto(r.imagePath, bytes);
      _records.add(r);
      added++;
    }
    for (final info in sampleInfos) {
      if (!_samples.containsKey(info.sampleId)) {
        _samples[info.sampleId] = info;
        samplesAdded++;
      }
    }
    _records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await _save();
    await _saveSamples();
    return (added, skipped, samplesAdded);
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
      }),
    );
    notifyListeners();
  }
}
