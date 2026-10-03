import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/calculator.dart';
import 'plate_record.dart';

/// Saved plates and settings, kept as JSON files in the app's documents folder.
/// Photos are copied into `<docs>/photos/` so they survive cache clearing.
class PlateStore extends ChangeNotifier {
  PlateStore(this.root);

  final Directory root;
  final List<PlateRecord> _records = [];
  CountingRule rule = CountingRule.fdaBam;
  double defaultVolumeMl = 0.1;

  static Future<PlateStore> open() async {
    final docs = await getApplicationDocumentsDirectory();
    final store = PlateStore(Directory('${docs.path}/colony_counter'));
    await store.load();
    return store;
  }

  List<PlateRecord> get records => List.unmodifiable(_records);
  Directory get photoDir => Directory('${root.path}/photos');
  File get _recordsFile => File('${root.path}/plates.json');
  File get _settingsFile => File('${root.path}/settings.json');

  File photoFile(PlateRecord r) => File('${photoDir.path}/${r.imagePath}');

  Future<void> load() async {
    await photoDir.create(recursive: true);
    _records.clear();
    if (await _recordsFile.exists()) {
      final list = jsonDecode(await _recordsFile.readAsString()) as List;
      _records.addAll(
        list.map((e) => PlateRecord.fromJson(e as Map<String, dynamic>)),
      );
      _records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    if (await _settingsFile.exists()) {
      final s = jsonDecode(
        await _settingsFile.readAsString(),
      ) as Map<String, dynamic>;
      rule = CountingRule.values.firstWhere(
        (r) => r.name == s['rule'],
        orElse: () => CountingRule.fdaBam,
      );
      defaultVolumeMl = (s['volume_ml'] as num?)?.toDouble() ?? 0.1;
    }
    notifyListeners();
  }

  /// Copies [source] into the photo folder and returns the stored file name.
  Future<String> importPhoto(File source, String id) async {
    final ext = source.path.contains('.')
        ? source.path.split('.').last.toLowerCase()
        : 'jpg';
    final name = '$id.$ext';
    await source.copy('${photoDir.path}/$name');
    return name;
  }

  Future<void> upsert(PlateRecord record) async {
    _records.removeWhere((r) => r.id == record.id);
    _records.add(record);
    _records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await _save();
  }

  Future<void> delete(PlateRecord record) async {
    _records.removeWhere((r) => r.id == record.id);
    final f = photoFile(record);
    if (await f.exists()) await f.delete();
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
    await _writeAtomic(
      _recordsFile,
      jsonEncode([for (final r in _records) r.toJson()]),
    );
    notifyListeners();
  }

  Future<void> _saveSettings() async {
    await _writeAtomic(
      _settingsFile,
      jsonEncode({'rule': rule.name, 'volume_ml': defaultVolumeMl}),
    );
    notifyListeners();
  }

  static Future<void> _writeAtomic(File f, String content) async {
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(content, flush: true);
    await tmp.rename(f.path);
  }
}
