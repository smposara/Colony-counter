import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/calculator.dart';
import 'plate_record.dart';
import 'storage/storage.dart';

/// Saved plates and settings, on top of a [StorageBackend] (files on phones,
/// IndexedDB in the browser).
class PlateStore extends ChangeNotifier {
  PlateStore(this.backend);

  final StorageBackend backend;
  final List<PlateRecord> _records = [];
  final Map<String, Uint8List> _photoCache = {};
  CountingRule rule = CountingRule.fdaBam;
  double defaultVolumeMl = 0.1;

  static const _recordsKey = 'plates';
  static const _settingsKey = 'settings';
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
    final settingsJson = await backend.readText(_settingsKey);
    if (settingsJson != null) {
      final s = jsonDecode(settingsJson) as Map<String, dynamic>;
      rule = CountingRule.values.firstWhere(
        (r) => r.name == s['rule'],
        orElse: () => CountingRule.fdaBam,
      );
      defaultVolumeMl = (s['volume_ml'] as num?)?.toDouble() ?? 0.1;
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

  /// Samples (by sample ID) with their plates, newest sample first.
  Map<String, List<PlateRecord>> samples() {
    final out = <String, List<PlateRecord>>{};
    for (final r in _records) {
      if (r.sampleId.isNotEmpty) (out[r.sampleId] ??= []).add(r);
    }
    return out;
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
      jsonEncode({'rule': rule.name, 'volume_ml': defaultVolumeMl}),
    );
    notifyListeners();
  }
}
