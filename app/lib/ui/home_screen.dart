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
import '../l10n/l10n.dart';
import '../l10n/labels.dart';
import 'about_screen.dart';
import 'accuracy_screen.dart';
import 'compare_screen.dart';
import 'format.dart';
import 'insets.dart';
import 'multi_plate_screen.dart';
import 'photo_flow.dart';
import 'photo_thumbnail.dart';
import 'review_screen.dart';
import 'samples_screen.dart';
import 'zone_results_screen.dart';
import 'zones_tab.dart';

/// The app's four areas: individual plates, samples (series and replicates),
/// comparisons between conditions, and inhibition-zone plates.
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
      2 => CompareTab(store: store),
      _ => ZonesTab(store: store),
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(
          [tr.appTitle, tr.homeSamples, tr.homeCompare, tr.homeZones][_tab],
        ),
        actions: [
          if (_tab == 0 && !store.defaultFormat.isFilm)
            IconButton(
              tooltip: tr.homeSeveralPlates,
              icon: const Icon(Icons.grid_view_outlined),
              onPressed: () => countSeveralPlates(context, store),
            ),
          if (_tab == 0)
            IconButton(
              tooltip: tr.homeImportPhoto,
              icon: const Icon(Icons.photo_library_outlined),
              onPressed: () => countNewPlate(context, store, fromGallery: true),
            ),
          if (_tab == 1)
            IconButton(
              tooltip: tr.homeScanLabel,
              icon: const Icon(Icons.qr_code_scanner),
              onPressed: () async {
                final label = await scanPlateLabel(context);
                if (label != null && context.mounted) {
                  await openFromLabel(context, store, label);
                }
              },
            ),
          if (_tab == 3)
            ListenableBuilder(
              listenable: store,
              builder: (context, _) => IconButton(
                tooltip: tr.zoneResults,
                icon: const Icon(Icons.bar_chart),
                onPressed: store.zoneRecords.isEmpty
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ZoneResultsScreen(store: store),
                        ),
                      ),
              ),
            ),
          _DataMenu(store: store, zones: _tab == 3),
        ],
      ),
      body: body,
      floatingActionButton: switch (_tab) {
        0 => FloatingActionButton.extended(
          onPressed: () => countNewPlate(context, store),
          icon: const Icon(Icons.camera_alt_outlined),
          label: Text(tr.homeCountPlate),
        ),
        1 => FloatingActionButton.extended(
          onPressed: () => openSampleSetup(context, store),
          icon: const Icon(Icons.add),
          label: Text(tr.homeNewSample),
        ),
        3 => FloatingActionButton.extended(
          onPressed: () => measureNewZonePlate(context, store),
          icon: const Icon(Icons.adjust),
          label: Text(tr.zonesMeasure),
        ),
        _ => null,
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.blur_circular),
            label: tr.homePlates,
          ),
          NavigationDestination(
            icon: const Icon(Icons.science_outlined),
            label: tr.homeSamples,
          ),
          NavigationDestination(
            icon: const Icon(Icons.show_chart),
            label: tr.homeCompare,
          ),
          NavigationDestination(
            icon: const Icon(Icons.adjust),
            label: tr.homeZones,
          ),
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
  const _DataMenu({required this.store, this.zones = false});

  final PlateStore store;

  /// On the Zones tab: the CSV export is the zone CSVs.
  final bool zones;

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
    if (zones) {
      await _share([
        ('zones_$stamp.csv', utf8.encode(zonesCsv(store)), 'text/csv'),
        (
          'zone_summary_$stamp.csv',
          utf8.encode(zoneSummaryCsv(store)),
          'text/csv',
        ),
      ], tr.zoneShareSubject);
      return;
    }
    await _share([
      ('plates_$stamp.csv', utf8.encode(platesCsv(store)), 'text/csv'),
      ('samples_$stamp.csv', utf8.encode(samplesCsv(store)), 'text/csv'),
      ('colonies_$stamp.csv', utf8.encode(coloniesCsv(store)), 'text/csv'),
      ('drops_$stamp.csv', utf8.encode(dropsCsv(store)), 'text/csv'),
    ], tr.homeShareCounts);
  }

  Future<void> _trainingExport(BuildContext context) async {
    final selection = await showDialog<TrainingSelection>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(tr.homeExportTraining),
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(tr.homeTrainingInfo),
          ),
          for (final s in TrainingSelection.values)
            ListTile(
              title: Text(s.text),
              trailing: Text('${trainingPlates(store, s).length}'),
              onTap: () => Navigator.pop(context, s),
            ),
        ],
      ),
    );
    if (selection == null || !context.mounted) return;
    if (trainingPlates(store, selection).isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr.homeNoPlatesToExport)));
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(content: Text(tr.homePreparingExport)));
    final zip = await buildTrainingExport(store, selection: selection);
    messenger.hideCurrentSnackBar();
    await _share([
      ('training_${_stamp()}.zip', zip, 'application/zip'),
    ], tr.homeShareTraining);
  }

  Future<void> _backup(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(content: Text(tr.homePreparingBackup)));
    final zip = await buildBackup(store);
    messenger.hideCurrentSnackBar();
    await _share([
      ('colony-counter-backup_${_stamp()}.zip', zip, 'application/zip'),
    ], tr.homeShareBackup);
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
      final plates = tr.homeNPlates(r.platesAdded);
      final samples = tr.homeNSamples(r.samplesAdded);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            r.platesSkipped > 0
                ? tr.homeRestoredKept(plates, samples, r.platesSkipped)
                : tr.homeRestored(plates, samples),
          ),
        ),
      );
    } on FormatException catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e.message.contains('not a zip')
                ? tr.restoreNotZip
                : tr.restoreNotBackup,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final empty =
        store.records.isEmpty &&
        store.samplePlans.isEmpty &&
        store.zoneRecords.isEmpty;
    return PopupMenuButton<String>(
      onSelected: (v) => switch (v) {
        'csv' => _exportCsv(),
        'backup' => _backup(context),
        'restore' => _restore(context),
        'accuracy' => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => AccuracyScreen(store: store)),
        ),
        'training' => _trainingExport(context),
        'about' => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const AboutScreen())),
        _ => showSettingsSheet(context, store),
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'csv',
          enabled: zones
              ? store.zoneRecords.isNotEmpty
              : store.records.isNotEmpty || store.samplePlans.isNotEmpty,
          child: Text(zones ? tr.zoneExportCsv : tr.homeExportCsv),
        ),
        PopupMenuItem(
          value: 'backup',
          enabled: !empty,
          child: Text(tr.homeBackUpAll),
        ),
        PopupMenuItem(value: 'restore', child: Text(tr.homeRestore)),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'accuracy', child: Text(tr.accuracyTitle)),
        PopupMenuItem(
          value: 'training',
          enabled: store.records.isNotEmpty,
          child: Text(tr.homeExportTraining),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'settings', child: Text(tr.homeSettings)),
        PopupMenuItem(value: 'about', child: Text(tr.aboutTitle)),
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
          padding: scrollPadding(
            context,
            const EdgeInsets.fromLTRB(16, 0, 16, 24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr.settingsLanguage,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: 'system',
                    label: Text(tr.languageSystem),
                  ),
                  const ButtonSegment(value: 'en', label: Text('English')),
                  const ButtonSegment(value: 'th', label: Text('ไทย')),
                ],
                selected: {store.language},
                onSelectionChanged: (s) {
                  // The app restarts its screens in the new language.
                  Navigator.of(context).pop();
                  store.setDefaults(language: s.first);
                },
              ),
              const SizedBox(height: 20),
              Text(
                tr.settingsTheme,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: 'system', label: Text(tr.themeSystem)),
                  ButtonSegment(value: 'light', label: Text(tr.themeLight)),
                  ButtonSegment(value: 'dark', label: Text(tr.themeDark)),
                ],
                selected: {store.theme},
                onSelectionChanged: (s) => store.setDefaults(theme: s.first),
              ),
              const SizedBox(height: 20),
              Text(
                tr.homeCountingRule,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              SegmentedButton<CountingRule>(
                showSelectedIcon: false,
                segments: [
                  for (final r in CountingRule.spreadRules)
                    ButtonSegment(value: r, label: Text(r.text)),
                ],
                selected: {store.rule},
                onSelectionChanged: (s) => store.setRule(s.first),
              ),
              const SizedBox(height: 4),
              Text(
                tr.homeCountableRange(store.rule.min, store.rule.max),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
              Text(
                tr.homeDefaultVolume,
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
                decoration: InputDecoration(
                  labelText: tr.homeDefaultPlateType,
                  helperText: tr.homeDefaultPlateTypeHelp,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  for (final f in PlateFormat.values)
                    if (!f.membrane)
                      DropdownMenuItem(value: f, child: Text(f.text)),
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
            Text(tr.homeNoPlates, style: t.titleLarge),
            const SizedBox(height: 8),
            Text(
              tr.homeEmptyHint,
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
          title: Text(tr.homeDeletePlate),
          content: Text(tr.homeDeletePlateBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr.homeCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr.homeDelete),
            ),
          ],
        ),
      ),
      onDismissed: (_) => store.delete(r),
      child: ListTile(
        leading: ClipOval(
          child: PhotoThumbnail(store: store, path: r.imagePath),
        ),
        title: Text(plateLabel(r)),
        subtitle: Text(
          r.isFilm
              ? '${shortDate(r.createdAt)}\n${filmSummary(r)}'
              : shortDate(r.createdAt),
        ),
        isThreeLine: r.isFilm,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (warn)
              Icon(Icons.warning_amber_rounded, color: cs.error, size: 20),
            if (unchecked)
              Tooltip(
                message: tr.homeFlagged,
                child: Icon(Icons.help_outline, color: cs.tertiary, size: 20),
              ),
            if (r.verified)
              Tooltip(
                message: tr.homeChecked,
                child: Icon(
                  Icons.fact_check_outlined,
                  color: cs.primary,
                  size: 20,
                ),
              ),
            if (r.seriesId.isNotEmpty)
              Tooltip(
                message: tr.homeTimelapse,
                child: Icon(Icons.timeline, color: cs.secondary, size: 20),
              ),
            const SizedBox(width: 6),
            Text(
              r.isFilm ? _filmValueText(r) : '${r.count}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
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

/// A film's main result, "≈" when estimated from grid squares (one tally).
String _filmValueText(PlateRecord r) {
  final t = r.filmTally;
  final k = t.counts.keys.first;
  final est = t.estimates?[k];
  return est == null
      ? formatCount(t.counts[k]!.toDouble())
      : '≈${formatCount(est)}';
}
