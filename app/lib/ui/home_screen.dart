import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../core/calculator.dart';
import '../data/plate_record.dart';
import '../data/plate_store.dart';
import 'capture_screen.dart';
import 'format.dart';
import 'review_screen.dart';
import 'samples_screen.dart';

/// Web photos are scaled to at most this many pixels on the long side. The
/// browser also applies the photo's rotation while scaling, so the pixels are
/// upright, and storage stays small.
const double _webMaxSide = 3000;

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.store});

  final PlateStore store;

  Future<void> _capture(BuildContext context) async {
    if (kIsWeb) {
      // In the browser, open the phone's own camera app (best image quality).
      await _pick(context, ImageSource.camera);
      return;
    }
    final path = await Navigator.of(context)
        .push<String>(MaterialPageRoute(builder: (_) => const CaptureScreen()));
    if (path == null || !context.mounted) return;
    final bytes = await XFile(path).readAsBytes();
    if (!context.mounted) return;
    await _review(context, bytes, guided: true);
  }

  Future<void> _pick(BuildContext context, ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: kIsWeb ? _webMaxSide : null,
      maxHeight: kIsWeb ? _webMaxSide : null,
      imageQuality: kIsWeb ? 92 : null,
    );
    if (picked == null || !context.mounted) return;
    final bytes = await picked.readAsBytes();
    if (!context.mounted) return;
    await _review(context, bytes, guided: false);
  }

  Future<void> _review(
    BuildContext context,
    Uint8List photo, {
    required bool guided,
  }) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ReviewScreen(store: store, photo: photo, guided: guided),
    ),
  );

  Future<void> _export(BuildContext context) async {
    if (store.records.isEmpty) return;
    final stamp = DateTime.now()
        .toIso8601String()
        .substring(0, 19)
        .replaceAll(':', '-');
    final name = 'colony_counts_$stamp.csv';
    final csv = utf8.encode(recordsToCsv(store.records, store.rule));
    // Phones open the share sheet; browsers that cannot share files download it.
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(csv, mimeType: 'text/csv', name: name)],
        fileNameOverrides: [name],
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
                onPressed: () => _pick(context, ImageSource.gallery),
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
          child: _Thumbnail(store: store, record: r),
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
