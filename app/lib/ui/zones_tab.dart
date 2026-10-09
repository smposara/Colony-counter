import 'package:flutter/material.dart';

import '../data/plate_store.dart';
import '../data/zone_record.dart';
import '../l10n/l10n.dart';
import 'format.dart';
import 'photo_flow.dart';
import 'photo_thumbnail.dart';
import 'zone_review_screen.dart';
import 'zone_setup_sheet.dart';

/// Sets up, photographs and measures a new zone plate.
Future<void> measureNewZonePlate(BuildContext context, PlateStore store) async {
  final choice = await showZoneSetupSheet(context, store);
  if (choice == null || !context.mounted) return;
  final photo = await takePlatePhoto(
    context,
    fromGallery: choice.fromGallery,
    format: choice.setup.format,
    tip: tr.zoneCaptureTip,
  );
  if (photo == null || !context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<ZoneRecord>(
      builder: (_) => ZoneReviewScreen(
        store: store,
        photo: photo.bytes,
        setup: choice.setup,
      ),
    ),
  );
}

/// Inhibition-zone plates, newest first.
class ZonesTab extends StatelessWidget {
  const ZonesTab({super.key, required this.store});

  final PlateStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final records = store.zoneRecords;
        if (records.isEmpty) return const _EmptyZones();
        return ListView.separated(
          padding: const EdgeInsets.only(bottom: 96),
          itemCount: records.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) =>
              ZoneRecordTile(store: store, record: records[i]),
        );
      },
    );
  }
}

class _EmptyZones extends StatelessWidget {
  const _EmptyZones();

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
              Icons.adjust,
              size: 72,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(tr.zonesNone, style: t.titleLarge),
            const SizedBox(height: 8),
            Text(
              tr.zonesEmptyHint,
              textAlign: TextAlign.center,
              style: t.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class ZoneRecordTile extends StatelessWidget {
  const ZoneRecordTile({super.key, required this.store, required this.record});

  final PlateStore store;
  final ZoneRecord record;

  @override
  Widget build(BuildContext context) {
    final r = record;
    final cs = Theme.of(context).colorScheme;
    final title = [
      if (r.experiment.isNotEmpty) r.experiment,
      if (r.organism.isNotEmpty) r.organism,
    ].join(' · ');
    return Dismissible(
      key: ValueKey('zone${r.id}'),
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
          title: Text(tr.zoneDeletePlate),
          content: Text(tr.zoneDeletePlateBody),
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
      onDismissed: (_) => store.deleteZone(r),
      child: ListTile(
        leading: ClipOval(
          child: PhotoThumbnail(store: store, path: r.imagePath),
        ),
        title: Text(title.isEmpty ? tr.zoneSetupTitle : title),
        subtitle: Text(
          '${tr.zoneRep(r.replicate)} · ${shortDate(r.createdAt)}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: r.checked
                  ? tr.zoneAllChecked
                  : tr.zoneNToCheck(
                      r.marks.where((m) => m.lowConfidence && !m.opened).length,
                    ),
              child: r.checked
                  ? Icon(Icons.fact_check_outlined, color: cs.primary, size: 20)
                  : Icon(Icons.help_outline, color: cs.tertiary, size: 20),
            ),
            const SizedBox(width: 6),
            Text(
              tr.zoneNZones(r.marks.length),
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ],
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<ZoneRecord>(
            builder: (_) => ZoneReviewScreen(store: store, record: r),
          ),
        ),
      ),
    );
  }
}
