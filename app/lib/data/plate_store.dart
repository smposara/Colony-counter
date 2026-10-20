import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/calculator.dart';
import '../core/plate.dart';
import 'plate_record.dart';
import 'export_source.dart';
import 'sample_info.dart';
import 'zone_calibration_record.dart';
import 'zone_record.dart';
import 'storage/storage.dart';
import 'storage/journaled_storage.dart';
import 'storage/serial_queue.dart';

/// Saved plates and settings, on top of a [StorageBackend] (files on phones,
/// IndexedDB in the browser).
class PlateStore extends ChangeNotifier implements ExportSource {
  PlateStore(StorageBackend backend)
    : backend = backend is JournaledStorage
          ? backend
          : JournaledStorage(backend);

  final JournaledStorage backend;
  final _mutations = SerialQueue();
  Map<String, String>? _pendingWrites;
  List<Future<void> Function()>? _afterCommit;
  List<String>? _newPhotos;
  Map<String, List<PlateRecord>>? _sampleIndex;
  Map<String, PlateRecord> _previousRecords = {};
  Map<String, ZoneRecord> _previousZones = {};
  bool _recordsIndexed = false, _zonesIndexed = false;

  String _recordKey(String collection, String id) =>
      '${collection}_${base64Url.encode(utf8.encode(id)).replaceAll('=', '')}';

  Future<List<dynamic>?> _readRecords(String collection) async {
    final index = await backend.readText('${collection}_index');
    if (index == null) {
      final legacy = await backend.readText(collection);
      return legacy == null ? null : jsonDecode(legacy) as List;
    }
    if (collection == _recordsKey) _recordsIndexed = true;
    if (collection == _zoneRecordsKey) _zonesIndexed = true;
    final ids = (jsonDecode(index) as List).cast<String>();
    final out = <dynamic>[];
    // Bound outstanding IndexedDB/file reads for large datasets.
    for (var start = 0; start < ids.length; start += 32) {
      final end = (start + 32).clamp(0, ids.length);
      final documents = await Future.wait([
        for (final id in ids.sublist(start, end))
          backend.readText(_recordKey(collection, id)),
      ]);
      for (final text in documents) {
        if (text == null) {
          throw const FormatException('Saved record is missing');
        }
        out.add(jsonDecode(text));
      }
    }
    return out;
  }

  Future<T> _mutate<T>(Future<T> Function() operation) =>
      _mutations.run(() async {
        final records = List.of(_records);
        _previousRecords = {for (final r in _records) r.id: r};
        _previousZones = {for (final r in _zoneRecords) r.id: r};
        final indexed = (_recordsIndexed, _zonesIndexed);
        final samples = Map.of(_samples);
        final zones = List.of(_zoneRecords);
        final panels = List.of(_zonePanels);
        final calibrations = List.of(_calibrations);
        final settings = (
          rule,
          defaultVolumeMl,
          defaultOperator,
          defaultMedium,
          defaultFormat,
          accuracyCheckEvery,
          language,
          theme,
          zoneSetup,
          zoneDisclaimerSeen,
          examplesOffered,
        );
        _sampleIndex = null;
        _pendingWrites = {};
        _afterCommit = [];
        _newPhotos = [];
        try {
          final result = await operation();
          await backend.writeDocuments(_pendingWrites!);
          _sampleIndex = null;
          final cleanup = _afterCommit!;
          _pendingWrites = null;
          _afterCommit = null;
          _newPhotos = null;
          notifyListeners();
          for (final action in cleanup) {
            try {
              await action();
            } catch (e) {
              // A cleanup failure leaves an unused photo, never a missing live photo.
              debugPrint('Photo cleanup deferred: $e');
            }
          }
          return result;
        } catch (_) {
          for (final name in _newPhotos ?? <String>[]) {
            try {
              await backend.deletePhoto(name);
            } catch (_) {
              /* unused photo */
            }
          }
          _records
            ..clear()
            ..addAll(records);
          _samples
            ..clear()
            ..addAll(samples);
          _zoneRecords
            ..clear()
            ..addAll(zones);
          _zonePanels
            ..clear()
            ..addAll(panels);
          _calibrations
            ..clear()
            ..addAll(calibrations);
          rule = settings.$1;
          defaultVolumeMl = settings.$2;
          defaultOperator = settings.$3;
          defaultMedium = settings.$4;
          defaultFormat = settings.$5;
          accuracyCheckEvery = settings.$6;
          language = settings.$7;
          theme = settings.$8;
          zoneSetup = settings.$9;
          zoneDisclaimerSeen = settings.$10;
          examplesOffered = settings.$11;
          _sampleIndex = null;
          _recordsIndexed = indexed.$1;
          _zonesIndexed = indexed.$2;
          notifyListeners();
          rethrow;
        } finally {
          _pendingWrites = null;
          _afterCommit = null;
          _newPhotos = null;
        }
      });

  /// Hold the mutation queue while a streaming export reads live photos.
  /// Cancellation/error releases the queue; no lock is acquired until listened to.
  Stream<T> readSnapshot<T>(Stream<T> Function() build) async* {
    final ready = Completer<void>();
    final release = Completer<void>();
    final gate = _mutations.run(() async {
      ready.complete();
      await release.future;
    });
    await ready.future;
    try {
      yield* build();
    } finally {
      release.complete();
      await gate;
    }
  }

  Future<void> _writeDocument(String key, String value) async {
    _pendingWrites![key] = value;
  }

  Future<void> _deletePhotoAfterCommit(String name) async {
    _afterCommit!.add(() async {
      if (_records.any((r) => r.imagePath == name) ||
          _zoneRecords.any((r) => r.imagePath == name)) {
        return;
      }
      await backend.deletePhoto(name);
    });
  }

  final List<PlateRecord> _records = [];
  final Map<String, Uint8List> _photoCache = {};
  final Map<String, SampleInfo> _samples = {};
  final List<ZoneRecord> _zoneRecords = [];
  final List<ZonePanel> _zonePanels = [];
  final List<CalibrationProfile> _calibrations = [];
  @override
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

  /// The built-in example data was offered at first launch (loaded if the
  /// app was empty), so it is never offered again.
  bool examplesOffered = false;

  static const _recordsKey = 'plates';
  static const _settingsKey = 'settings';
  static const _samplesKey = 'samples';
  static const _zoneRecordsKey = 'zone_plates';
  static const _zonePanelsKey = 'zone_panels';
  static const _calibrationsKey = 'zone_calibrations';
  static const photoCacheBudget = 24 * 1024 * 1024;
  int _photoCacheBytes = 0;

  @visibleForTesting
  int get cachedPhotoBytes => _photoCacheBytes;

  void _evictPhoto(String name) {
    _photoCacheBytes -= _photoCache.remove(name)?.lengthInBytes ?? 0;
  }

  static Future<PlateStore> open() async {
    final store = PlateStore(await openDefaultStorage());
    await store.load();
    return store;
  }

  @override
  List<PlateRecord> get records => List.unmodifiable(_records);

  /// Inhibition-zone plates, newest first.
  @override
  List<ZoneRecord> get zoneRecords => List.unmodifiable(_zoneRecords);

  /// Saved label panels for zone plates.
  List<ZonePanel> get zonePanels => List.unmodifiable(_zonePanels);

  /// Zone calibration profiles (calliper against the app), newest first.
  @override
  List<CalibrationProfile> get calibrations => List.unmodifiable(_calibrations);

  Future<void> load() async {
    _recordsIndexed = false;
    _zonesIndexed = false;
    _sampleIndex = null;
    _records.clear();
    final list = await _readRecords(_recordsKey);
    if (list != null) {
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
    final zoneList = await _readRecords(_zoneRecordsKey);
    if (zoneList != null) {
      for (final e in zoneList) {
        _zoneRecords.add(ZoneRecord.fromJson(e as Map<String, dynamic>));
      }
      _zoneRecords.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    _calibrations.clear();
    final calJson = await backend.readText(_calibrationsKey);
    if (calJson != null) {
      for (final e in jsonDecode(calJson) as List) {
        _calibrations.add(
          CalibrationProfile.fromJson(e as Map<String, dynamic>),
        );
      }
      _sortCalibrations();
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
      examplesOffered = s['examples_offered'] as bool? ?? false;
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
    if (cached != null) {
      _photoCache.remove(name);
      _photoCache[name] = cached;
      return cached;
    }
    final bytes = await backend.readPhoto(name);
    if (bytes != null) _cachePhoto(name, bytes);
    return bytes;
  }

  void _cachePhoto(String name, Uint8List bytes) {
    _evictPhoto(name);
    if (bytes.lengthInBytes > photoCacheBudget) return;
    _photoCache[name] = bytes;
    _photoCacheBytes += bytes.lengthInBytes;
    while (_photoCacheBytes > photoCacheBudget) {
      _evictPhoto(_photoCache.keys.first);
    }
  }

  /// Saves a capture and the optional first time-lapse frame in one commit.
  /// The same draft ID can safely be retried after an I/O failure.
  Future<PlateRecord> saveCapture(
    PlateRecord record,
    Uint8List? photo, {
    PlateRecord? firstFrame,
  }) => _mutate(() async {
    var saved = record;
    if (photo != null) {
      final name = safePhotoName('${record.id}.jpg', record.id);
      if (_records.any((r) => r.imagePath == name) ||
          _zoneRecords.any((r) => r.imagePath == name)) {
        throw StateError('Photo already belongs to a saved plate');
      }
      _newPhotos!.add(name);
      await backend.writePhoto(name, photo);
      saved = PlateRecord.fromJson({...record.toJson(), 'image': name});
    }
    if (firstFrame != null) {
      _records.removeWhere((r) => r.id == firstFrame.id);
      _records.add(firstFrame);
    }
    _records.removeWhere((r) => r.id == saved.id);
    _records.add(saved);
    _records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await _save();
    return saved;
  });

  Future<ZoneRecord> saveZoneCapture(ZoneRecord record, Uint8List? photo) =>
      _mutate(() async {
        var saved = record;
        if (photo != null) {
          final name = safePhotoName('zone_${record.id}.jpg', record.id);
          if (_records.any((r) => r.imagePath == name) ||
              _zoneRecords.any((r) => r.imagePath == name)) {
            throw StateError('Photo already belongs to a saved plate');
          }
          _newPhotos!.add(name);
          await backend.writePhoto(name, photo);
          saved = ZoneRecord.fromJson({...record.toJson(), 'image': name});
        }
        _zoneRecords.removeWhere((r) => r.id == saved.id);
        _zoneRecords.add(saved);
        _zoneRecords.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        await _saveZones();
        return saved;
      });

  Future<void> upsert(PlateRecord record) => _mutate(() async {
    _records.removeWhere((r) => r.id == record.id);
    _records.add(record);
    _records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await _save();
  });

  Future<void> delete(PlateRecord record) => _mutate(() async {
    _records.removeWhere((r) => r.id == record.id);
    _evictPhoto(record.imagePath);
    await _deletePhotoAfterCommit(record.imagePath);
    await _save();
  });

  Future<void> upsertZone(ZoneRecord record) => _mutate(() async {
    _zoneRecords.removeWhere((r) => r.id == record.id);
    _zoneRecords.add(record);
    _zoneRecords.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await _saveZones();
  });

  Future<void> deleteZone(ZoneRecord record) => _mutate(() async {
    _zoneRecords.removeWhere((r) => r.id == record.id);
    _evictPhoto(record.imagePath);
    await _deletePhotoAfterCommit(record.imagePath);
    await _saveZones();
  });

  /// Adds or replaces the panel called [panel]'s name.
  Future<void> savePanel(ZonePanel panel) => _mutate(() async {
    final i = _zonePanels.indexWhere((p) => p.name == panel.name);
    if (i < 0) {
      _zonePanels.add(panel);
    } else {
      _zonePanels[i] = panel;
    }
    await _savePanels();
  });

  Future<void> deletePanel(String name) => _mutate(() async {
    _zonePanels.removeWhere((p) => p.name == name);
    await _savePanels();
  });

  Future<void> upsertCalibration(CalibrationProfile profile) =>
      _mutate(() async {
        _calibrations.removeWhere((p) => p.id == profile.id);
        _calibrations.add(profile);
        _sortCalibrations();
        await _saveCalibrations();
      });

  /// Deletes the profile; its plates stay as ordinary zone plates.
  Future<void> deleteCalibration(CalibrationProfile profile) =>
      _mutate(() async {
        _calibrations.removeWhere((p) => p.id == profile.id);
        // Its plates become ordinary zone plates again (readings are kept).
        var changed = false;
        for (var i = 0; i < _zoneRecords.length; i++) {
          final r = _zoneRecords[i];
          if (r.calibrationId != profile.id) continue;
          _zoneRecords[i] = r.copyWith(
            calibrationId: '',
            usedForCalibration: false,
          );
          changed = true;
        }
        if (changed) await _saveZones();
        await _saveCalibrations();
      });

  void _sortCalibrations() =>
      _calibrations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  Future<void> _saveCalibrations() async {
    await _writeDocument(
      _calibrationsKey,
      jsonEncode([for (final p in _calibrations) p.toJson()]),
    );
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

  Future<void> setRule(CountingRule r) => _mutate(() async {
    rule = r;
    await _saveSettings();
  });

  Future<void> setDefaultVolume(double v) => _mutate(() async {
    defaultVolumeMl = v;
    await _saveSettings();
  });

  Future<void> setDefaults({
    String? operator,
    String? medium,
    PlateFormat? format,
    int? accuracyCheckEvery,
    String? language,
    String? theme,
    ZoneSetup? zoneSetup,
    bool? zoneDisclaimerSeen,
  }) => _mutate(() async {
    this.language = language ?? this.language;
    this.theme = theme ?? this.theme;
    this.zoneSetup = zoneSetup ?? this.zoneSetup;
    this.zoneDisclaimerSeen = zoneDisclaimerSeen ?? this.zoneDisclaimerSeen;
    defaultOperator = operator ?? defaultOperator;
    defaultMedium = medium ?? defaultMedium;
    defaultFormat = format ?? defaultFormat;
    this.accuracyCheckEvery = accuracyCheckEvery ?? this.accuracyCheckEvery;
    await _saveSettings();
  });

  Future<void> acceptZoneDisclaimer() => _mutate(() async {
    zoneDisclaimerSeen = true;
    await _saveSettings();
  });

  Future<void> setExamplesOffered() => _mutate(() async {
    examplesOffered = true;
    await _saveSettings();
  });

  Future<void> setZoneSetup(ZoneSetup setup) => _mutate(() async {
    zoneSetup = setup;
    await _saveSettings();
  });

  /// Plates grouped by sample ID.
  Map<String, List<PlateRecord>> get _indexedSamples {
    if (_sampleIndex != null) return _sampleIndex!;
    final index = <String, List<PlateRecord>>{};
    for (final r in _records) {
      (index[r.sampleId] ??= []).add(r);
    }
    return _sampleIndex = index;
  }

  Map<String, List<PlateRecord>> samples() => {
    for (final e in _indexedSamples.entries)
      if (e.key.isNotEmpty) e.key: List.of(e.value),
  };

  @override
  List<PlateRecord> platesOf(String sampleId) =>
      List.of(_indexedSamples[sampleId] ?? const <PlateRecord>[]);

  /// Every known sample: those set up in advance and those with plates,
  /// newest first.
  @override
  List<SampleInfo> allSamples() {
    final ids = {
      ..._samples.keys,
      ..._indexedSamples.keys.where((id) => id.isNotEmpty),
    };
    final list = [for (final id in ids) sampleInfo(id)];
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  /// The saved plan for [id], or one inferred from its plates.
  @override
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

  Future<void> upsertSample(SampleInfo info, {String? previousId}) =>
      _mutate(() async {
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
      });

  /// Removes the sample plan; with [withPlates] also deletes its plates.
  Future<void> deleteSample(String id, {bool withPlates = false}) =>
      _mutate(() async {
        _samples.remove(id);
        if (withPlates) {
          for (final r in platesOf(id)) {
            _evictPhoto(r.imagePath);
            await _deletePhotoAfterCommit(r.imagePath);
          }
          _records.removeWhere((r) => r.sampleId == id);
          await _save();
        }
        await _saveSamples();
      });

  /// Adds plates, samples and photos from a backup. Items whose ID already
  /// exists here are skipped. With [onlyIntoEmpty], nothing is added unless
  /// there are no plates, samples or zone plates here when the import runs
  /// (checked in the same mutation, so nothing saved meanwhile is missed).
  /// Returns (plates added, plates skipped, samples added).
  Future<(int, int, int)> importAll(
    List<PlateRecord> plates,
    List<SampleInfo> sampleInfos,
    Future<Uint8List?> Function(String imagePath) photo, {
    List<ZoneRecord> zonePlates = const [],
    List<ZonePanel> zonePanels = const [],
    List<CalibrationProfile> calibrations = const [],
    bool onlyIntoEmpty = false,
  }) => _mutate(() async {
    if (onlyIntoEmpty &&
        (_records.isNotEmpty ||
            _samples.isNotEmpty ||
            _zoneRecords.isNotEmpty)) {
      return (0, 0, 0);
    }
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
      _evictPhoto(safe);
      if (bytes != null) {
        _newPhotos!.add(safe);
        await backend.writePhoto(safe, bytes);
      }
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
      _evictPhoto(safe);
      if (bytes != null) {
        _newPhotos!.add(safe);
        await backend.writePhoto(safe, bytes);
      }
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
    // Calibration profiles: known IDs are kept as they are.
    final haveCal = {for (final p in _calibrations) p.id};
    var calAdded = 0;
    for (final p in calibrations) {
      if (haveCal.add(p.id)) {
        _calibrations.add(p);
        calAdded++;
      }
    }
    if (calAdded > 0) {
      _sortCalibrations();
      await _saveCalibrations();
    }
    if (zonePlates.isNotEmpty || zonePanels.isNotEmpty) {
      await _saveZones();
      await _savePanels();
    }
    return (added + zonesAdded, skipped, samplesAdded);
  });

  List<SampleInfo> get samplePlans => List.unmodifiable(_samples.values);

  Future<void> _saveSamples() async {
    await _writeDocument(
      _samplesKey,
      jsonEncode([for (final s in _samples.values) s.toJson()]),
    );
  }

  Future<void> _save() async {
    _sampleIndex = null;
    for (final r in _records) {
      if (!_recordsIndexed || !identical(_previousRecords[r.id], r)) {
        await _writeDocument(
          _recordKey(_recordsKey, r.id),
          jsonEncode(r.toJson()),
        );
      }
    }
    final ids = {for (final r in _records) r.id};
    for (final id in _previousRecords.keys.where((id) => !ids.contains(id))) {
      await _writeDocument(_recordKey(_recordsKey, id), 'null');
    }
    await _writeDocument(
      '${_recordsKey}_index',
      jsonEncode([for (final r in _records) r.id]),
    );
    if (!_recordsIndexed) await _writeDocument(_recordsKey, '[]');
    _recordsIndexed = true;
  }

  Future<void> _saveZones() async {
    for (final r in _zoneRecords) {
      if (!_zonesIndexed || !identical(_previousZones[r.id], r)) {
        await _writeDocument(
          _recordKey(_zoneRecordsKey, r.id),
          jsonEncode(r.toJson()),
        );
      }
    }
    final ids = {for (final r in _zoneRecords) r.id};
    for (final id in _previousZones.keys.where((id) => !ids.contains(id))) {
      await _writeDocument(_recordKey(_zoneRecordsKey, id), 'null');
    }
    await _writeDocument(
      '${_zoneRecordsKey}_index',
      jsonEncode([for (final r in _zoneRecords) r.id]),
    );
    if (!_zonesIndexed) await _writeDocument(_zoneRecordsKey, '[]');
    _zonesIndexed = true;
  }

  Future<void> _savePanels() async {
    await _writeDocument(
      _zonePanelsKey,
      jsonEncode([for (final p in _zonePanels) p.toJson()]),
    );
  }

  Future<void> _saveSettings() async {
    await _writeDocument(
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
        'examples_offered': examplesOffered,
      }),
    );
  }
}

/// [name] if it is a plain file name, otherwise a safe name made from [id].
String safePhotoName(String name, String id) {
  final plain = RegExp(r'^[A-Za-z0-9_-][A-Za-z0-9._-]*$');
  if (plain.hasMatch(name) && !name.contains('..')) return name;
  final cleaned = id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  return 'restored_${cleaned.isEmpty ? 'photo' : cleaned}.jpg';
}
