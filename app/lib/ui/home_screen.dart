import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/calculator.dart';
import '../core/pipeline.dart';
import '../core/plate.dart';
import '../data/export.dart';
import '../data/plate_record.dart';
import '../data/plate_store.dart';
import '../data/training_export.dart';
import 'accuracy_screen.dart';
import 'compare_screen.dart';
import 'format.dart';
import 'multi_plate_screen.dart';
import 'photo_flow.dart';
import 'review_screen.dart';
import 'samples_screen.dart';

/// The app's three areas: individual plates, samples (series and replicates),
/// and comparisons between conditions.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store});

  final PlateStore store;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  PlateStore get store => widget.store;

  @override
  Widget build(BuildContext context) {
    final body = switch (_tab) {
      0 => _PlatesTab(store: store),
      1 => SamplesTab(store: store),
      _ => CompareTab(store: store),
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(const ['Colony Counter', 'Samples', 'Compare'][_tab]),
        actions: [
          if (_tab == 0)
            IconButton(
              tooltip: 'Several plates in one photo',
              icon: const Icon(Icons.grid_view_outlined),
              onPressed: () => countSeveralPlates(context, store),
            ),
          if (_tab == 0)
            IconButton(
              tooltip: 'Import photo',
              icon: const Icon(Icons.photo_library_outlined),
              onPressed: () => countNewPlate(context, store, fromGallery: true),
            ),
          if (_tab == 1)
            IconButton(
              tooltip: 'Scan plate label',
              icon: const Icon(Icons.qr_code_scanner),
              onPressed: () async {
                final label = await scanPlateLabel(context);
                if (label != null && context.mounted) {
                  await openFromLabel(context, store, label);
                }
              },
            ),
          _DataMenu(store: store),
        ],
      ),
      body: body,
      floatingActionButton: switch (_tab) {
        0 => FloatingActionButton.extended(
          onPressed: () => countNewPlate(context, store),
          icon: const Icon(Icons.camera_alt_outlined),
          label: const Text('Count plate'),
        ),
        1 => FloatingActionButton.extended(
          onPressed: () => openSampleSetup(context, store),
          icon: const Icon(Icons.add),
          label: const Text('New sample'),
        ),
        _ => null,
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.blur_circular),
            label: 'Plates',
          ),
          NavigationDestination(
            icon: Icon(Icons.science_outlined),
            label: 'Samples',
          ),
          NavigationDestination(icon: Icon(Icons.show_chart), label: 'Compare'),
        ],
      ),
    );
  }
}

class _PlatesTab extends StatelessWidget {
  const _PlatesTab({required this.store});

  final PlateStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final records = store.records;
        if (records.isEmpty) return const _EmptyState();
        return ListView.separated(
          padding: const EdgeInsets.only(bottom: 96),
          itemCount: records.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) =>
              RecordTile(store: store, record: records[i]),
        );
      },
    );
  }
}

/// Export, backup, restore and settings.
class _DataMenu extends StatelessWidget {
  const _DataMenu({required this.store});

  final PlateStore store;

  static String _stamp() =>
      DateTime.now().toIso8601String().substring(0, 19).replaceAll(':', '-');

  Future<void> _share(
    List<(String, List<int>, String)> files,
    String subject,
  ) async {
    // Phones open the share sheet; browsers that cannot share files download them.
    await SharePlus.instance.share(
      ShareParams(
        files: [
          for (final (name, bytes, mime) in files)
            XFile.fromData(
              Uint8List.fromList(bytes),
              mimeType: mime,
              name: name,
            ),
        ],
        fileNameOverrides: [for (final f in files) f.$1],
        subject: subject,
      ),
    );
  }

  Future<void> _exportCsv() async {
    final stamp = _stamp();
    await _share([
      ('plates_$stamp.csv', utf8.encode(platesCsv(store)), 'text/csv'),
      ('samples_$stamp.csv', utf8.encode(samplesCsv(store)), 'text/csv'),
      ('colonies_$stamp.csv', utf8.encode(coloniesCsv(store)), 'text/csv'),
    ], 'Colony counts');
  }

  Future<void> _trainingExport(BuildContext context) async {
    final selection = await showDialog<TrainingSelection>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Export training data'),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              'Photos with every colony mark, in COCO and YOLO formats, for '
              'training a colony detector on your own plates.',
            ),
          ),
          for (final s in TrainingSelection.values)
            ListTile(
              title: Text(s.label),
              trailing: Text('${trainingPlates(store, s).length}'),
              onTap: () => Navigator.pop(context, s),
            ),
        ],
      ),
    );
    if (selection == null || !context.mounted) return;
    if (trainingPlates(store, selection).isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No plates to export.')));
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Preparing export…')));
    final zip = await buildTrainingExport(store, selection: selection);
    messenger.hideCurrentSnackBar();
    await _share([
      ('training_${_stamp()}.zip', zip, 'application/zip'),
    ], 'Colony Counter training data');
  }

  Future<void> _backup(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Preparing backup…')));
    final zip = await buildBackup(store);
    messenger.hideCurrentSnackBar();
    await _share([
      ('colony-counter-backup_${_stamp()}.zip', zip, 'application/zip'),
    ], 'Colony Counter backup');
  }

  Future<void> _restore(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    if (picked.isEmpty) return;
    final bytes = await picked.single.readAsBytes();
    try {
      final r = await restoreBackup(store, bytes);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Restored ${r.platesAdded} plate${r.platesAdded == 1 ? '' : 's'}'
            ' and ${r.samplesAdded} sample${r.samplesAdded == 1 ? '' : 's'}'
            '${r.platesSkipped > 0 ? ' (${r.platesSkipped} already here, kept)' : ''}.',
          ),
        ),
      );
    } on FormatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final empty = store.records.isEmpty && store.samplePlans.isEmpty;
    return PopupMenuButton<String>(
      onSelected: (v) => switch (v) {
        'csv' => _exportCsv(),
        'backup' => _backup(context),
        'restore' => _restore(context),
        'accuracy' => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => AccuracyScreen(store: store)),
        ),
        'training' => _trainingExport(context),
        _ => showSettingsSheet(context, store),
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'csv',
          enabled: !empty,
          child: const Text('Export CSV'),
        ),
        PopupMenuItem(
          value: 'backup',
          enabled: !empty,
          child: const Text('Back up all data'),
        ),
        const PopupMenuItem(
          value: 'restore',
          child: Text('Restore from backup'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'accuracy',
          child: Text('Counting accuracy'),
        ),
        PopupMenuItem(
          value: 'training',
          enabled: store.records.isNotEmpty,
          child: const Text('Export training data'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'settings', child: Text('Settings')),
      ],
    );
  }
}

void showSettingsSheet(BuildContext context, PlateStore store) =>
    _SettingsLauncher(store)._showSettings(context);

class _SettingsLauncher {
  _SettingsLauncher(this.store);

  final PlateStore store;

  void _showSettings(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Counting rule',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              SegmentedButton<CountingRule>(
                showSelectedIcon: false,
                segments: [
                  for (final r in CountingRule.spreadRules)
                    ButtonSegment(value: r, label: Text(r.label)),
                ],
                selected: {store.rule},
                onSelectionChanged: (s) => store.setRule(s.first),
              ),
              const SizedBox(height: 4),
              Text(
                'Countable range: ${store.rule.min}–${store.rule.max} colonies per plate',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
              Text(
                'Default plated volume',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              SegmentedButton<double>(
                segments: const [
                  ButtonSegment(value: 0.1, label: Text('0.1 mL')),
                  ButtonSegment(value: 0.2, label: Text('0.2 mL')),
                  ButtonSegment(value: 1.0, label: Text('1.0 mL')),
                ],
                selected: {store.defaultVolumeMl},
                onSelectionChanged: (s) => store.setDefaultVolume(s.first),
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<PlateFormat>(
                isExpanded: true,
                initialValue: store.defaultFormat,
                decoration: const InputDecoration(
                  labelText: 'Default plate type',
                  helperText: 'For quick counts and new samples',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final f in PlateFormat.values)
                    if (!f.membrane)
                      DropdownMenuItem(value: f, child: Text(f.label)),
                ],
                onChanged: (f) => store.setDefaults(format: f),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.blur_circular,
              size: 72,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text('No plates yet', style: t.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Place a 90 mm Nutrient Agar plate in the lightbox with the lid off, '
              'then tap “Count plate”.',
              textAlign: TextAlign.center,
              style: t.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class RecordTile extends StatelessWidget {
  const RecordTile({super.key, required this.store, required this.record});

  final PlateStore store;
  final PlateRecord record;

  @override
  Widget build(BuildContext context) {
    final r = record;
    final cs = Theme.of(context).colorScheme;
    final warn =
        r.spreader ||
        r.tntc ||
        r.flags.contains('tntc') ||
        r.flags.contains('spreader');
    // Flagged for checking but saved without any correction or check.
    final unchecked =
        !warn &&
        !r.verified &&
        r.count == r.autoCount &&
        r.rejected.isEmpty &&
        r.flags.any(kCheckFlags.contains);
    return Dismissible(
      key: ValueKey(r.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: cs.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Icon(Icons.delete_outline, color: cs.onErrorContainer),
      ),
      confirmDismiss: (_) => showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete plate?'),
          content: const Text(
            'The photo and its count will be removed from this phone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
      onDismissed: (_) => store.delete(r),
      child: ListTile(
        leading: ClipOval(
          child: _Thumbnail(store: store, record: r),
        ),
        title: Text(plateLabel(r)),
        subtitle: Text(shortDate(r.createdAt)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (warn)
              Icon(Icons.warning_amber_rounded, color: cs.error, size: 20),
            if (unchecked)
              Tooltip(
                message: 'Flagged for checking',
                child: Icon(Icons.help_outline, color: cs.tertiary, size: 20),
              ),
            if (r.verified)
              Tooltip(
                message: 'Checked every colony',
                child: Icon(
                  Icons.fact_check_outlined,
                  color: cs.primary,
                  size: 20,
                ),
              ),
            if (r.seriesId.isNotEmpty)
              Tooltip(
                message: 'Time-lapse',
                child: Icon(Icons.timeline, color: cs.secondary, size: 20),
              ),
            const SizedBox(width: 6),
            Text('${r.count}', style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ReviewScreen(store: store, record: r),
          ),
        ),
      ),
    );
  }
}

class _Thumbnail extends StatefulWidget {
  const _Thumbnail({required this.store, required this.record});

  final PlateStore store;
  final PlateRecord record;

  @override
  State<_Thumbnail> createState() => _ThumbnailState();
}

class _ThumbnailState extends State<_Thumbnail> {
  late Future<Uint8List?> _photo = widget.store.readPhoto(widget.record);

  @override
  void didUpdateWidget(_Thumbnail old) {
    super.didUpdateWidget(old);
    if (old.record.imagePath != widget.record.imagePath) {
      _photo = widget.store.readPhoto(widget.record);
    }
  }

  @override
  Widget build(BuildContext context) {
    const empty = SizedBox(width: 48, height: 48);
    return FutureBuilder<Uint8List?>(
      future: _photo,
      builder: (context, snap) {
        final bytes = snap.data;
        if (bytes == null) return empty;
        return Image.memory(
          bytes,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          cacheWidth: 144,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => empty,
        );
      },
    );
  }
}
