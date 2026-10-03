import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/calculator.dart';
import '../data/plate_record.dart';
import '../data/plate_store.dart';
import 'capture_screen.dart';
import 'format.dart';
import 'review_screen.dart';
import 'samples_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.store});

  final PlateStore store;

  Future<void> _capture(BuildContext context) async {
    final path = await Navigator.of(context)
        .push<String>(MaterialPageRoute(builder: (_) => const CaptureScreen()));
    if (path == null || !context.mounted) return;
    await _review(context, File(path), guided: true);
  }

  Future<void> _import(BuildContext context) async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null || !context.mounted) return;
    await _review(context, File(picked.path), guided: false);
  }

  Future<void> _review(
    BuildContext context,
    File photo, {
    required bool guided,
  }) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ReviewScreen(store: store, photo: photo, guided: guided),
    ),
  );

  Future<void> _export(BuildContext context) async {
    if (store.records.isEmpty) return;
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now()
        .toIso8601String()
        .substring(0, 19)
        .replaceAll(':', '-');
    final file = File('${dir.path}/colony_counts_$stamp.csv');
    await file.writeAsString(recordsToCsv(store.records, store.rule));
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        subject: 'Colony counts',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final records = store.records;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Colony Counter'),
            actions: [
              IconButton(
                tooltip: 'Samples & CFU/mL',
                icon: const Icon(Icons.science_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SamplesScreen(store: store),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Import photo',
                icon: const Icon(Icons.photo_library_outlined),
                onPressed: () => _import(context),
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'export') _export(context);
                  if (v == 'settings') _showSettings(context);
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'export',
                    enabled: records.isNotEmpty,
                    child: const Text('Export CSV'),
                  ),
                  const PopupMenuItem(
                    value: 'settings',
                    child: Text('Settings'),
                  ),
                ],
              ),
            ],
          ),
          body: records.isEmpty
              ? const _EmptyState()
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: records.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) =>
                      _RecordTile(store: store, record: records[i]),
                ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _capture(context),
            icon: const Icon(Icons.camera_alt_outlined),
            label: const Text('Count plate'),
          ),
        );
      },
    );
  }

  void _showSettings(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) => Padding(
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
                  for (final r in CountingRule.values)
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

class _RecordTile extends StatelessWidget {
  const _RecordTile({required this.store, required this.record});

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
          child: Image.file(
            store.photoFile(r),
            width: 48,
            height: 48,
            fit: BoxFit.cover,
            cacheWidth: 144,
            errorBuilder: (_, _, _) => const SizedBox(width: 48, height: 48),
          ),
        ),
        title: Text(
          r.sampleId.isEmpty
              ? 'Unlabelled · ${dilutionLabel(r.dilutionExp)}'
              : '${r.sampleId} · ${dilutionLabel(r.dilutionExp)}',
        ),
        subtitle: Text(shortDate(r.createdAt)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (warn)
              Icon(Icons.warning_amber_rounded, color: cs.error, size: 20),
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
