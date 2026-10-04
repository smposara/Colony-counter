import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/calculator.dart';
import '../core/labels.dart';
import '../core/stats.dart';
import '../data/plate_record.dart';
import '../data/label_sheet.dart';
import '../data/plate_store.dart';
import '../data/sample_info.dart';
import 'format.dart';
import 'home_screen.dart';
import 'photo_flow.dart';
import 'review_screen.dart';
import 'sample_setup_screen.dart';

Future<void> openSampleSetup(
  BuildContext context,
  PlateStore store, {
  SampleInfo? edit,
  SampleInfo? template,
  String? initialId,
}) async {
  final saved = await Navigator.of(context).push<SampleInfo>(
    MaterialPageRoute(
      builder: (_) => SampleSetupScreen(
        store: store,
        edit: edit,
        template: template,
        initialId: initialId,
      ),
    ),
  );
  if (saved == null || !context.mounted || edit != null) return;
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) =>
          SampleDetailScreen(store: store, sampleId: saved.sampleId),
    ),
  );
}

/// Opens the sample a scanned label points to. When the label names a plate
/// that has not been counted yet, offers to photograph it straight away.
Future<void> openFromLabel(
  BuildContext context,
  PlateStore store,
  PlateLabel label,
) async {
  final known = store.allSamples().any((s) => s.sampleId == label.sampleId);
  if (!known) {
    final create = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Sample “${label.sampleId}” not found'),
        content: const Text('Set up this sample now?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Set up'),
          ),
        ],
      ),
    );
    if ((create ?? false) && context.mounted) {
      await openSampleSetup(context, store, initialId: label.sampleId);
    }
    return;
  }
  final info = store.sampleInfo(label.sampleId);
  final slot = store.hasPlan(label.sampleId)
      ? info.slots
            .where(
              (s) =>
                  s.dilutionExp == label.dilutionExp &&
                  s.replicate == label.replicate,
            )
            .firstOrNull
      : null;
  final done = slot != null && store.platesOf(label.sampleId).any(slot.matches);
  if (slot != null && !done) {
    final shoot = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(label.caption.replaceAll('10^-', '10⁻')),
        content: const Text('Photograph this plate now?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Just open sample'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Photograph'),
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    if (shoot ?? false) {
      await countNewPlate(
        context,
        store,
        preset: PlatePreset(info: info, slot: slot),
      );
      return;
    }
  } else if (done) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${label.caption} is already counted.')),
    );
  }
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) =>
          SampleDetailScreen(store: store, sampleId: label.sampleId),
    ),
  );
}

/// "log₁₀ 6.21 ± 0.08 (n = 3)" for a sample result.
String resultSummary(SampleResult r) {
  final s = r.stats;
  if (s.n == 0) return 'No result yet';
  final sd = s.n > 1 ? ' ± ${fixed(s.log10Sd)}' : '';
  return 'log₁₀ ${fixed(s.log10Mean)}$sd (n = ${s.n})${r.qualified ? ' · est.' : ''}';
}

String hoursLabel(double h) => '${fixed(h, h % 1 == 0 ? 0 : 1)} h';

/// Samples grouped by experiment, newest first.
class SamplesTab extends StatefulWidget {
  const SamplesTab({super.key, required this.store});

  final PlateStore store;

  @override
  State<SamplesTab> createState() => _SamplesTabState();
}

class _SamplesTabState extends State<SamplesTab> {
  String _query = '';

  PlateStore get store => widget.store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final all = store.allSamples();
        final samples = [
          for (final s in all)
            if (s.matches(_query)) s,
        ];
        if (all.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'Set up a sample to plan its dilution series and replicates. '
                'The app then tells you which plate to photograph next and '
                'reports mean ± SD and log₁₀ CFU/mL across replicates.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        final groups = <String, List<SampleInfo>>{};
        for (final s in samples) {
          (groups[s.experiment] ??= []).add(s);
        }
        // Within an experiment: by condition, then time point.
        for (final list in groups.entries.where((e) => e.key.isNotEmpty)) {
          list.value.sort(
            (a, b) => a.condition != b.condition
                ? a.condition.compareTo(b.condition)
                : (a.timeH ?? -1).compareTo(b.timeH ?? -1),
          );
        }
        // Named experiments alphabetically, then samples without one.
        final names = groups.keys.toList()
          ..sort((a, b) => a.isEmpty ? 1 : (b.isEmpty ? -1 : a.compareTo(b)));
        return ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search sample, strain, operator, tag…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            if (samples.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No samples match.', textAlign: TextAlign.center),
              ),
            for (final name in names) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(
                  name.isEmpty ? 'No experiment' : name,
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(color: Theme.of(context).colorScheme.primary),
                ),
              ),
              for (final s in groups[name]!) _SampleTile(store: store, info: s),
            ],
          ],
        );
      },
    );
  }
}

class _SampleTile extends StatelessWidget {
  const _SampleTile({required this.store, required this.info});

  final PlateStore store;
  final SampleInfo info;

  @override
  Widget build(BuildContext context) {
    final plates = store.platesOf(info.sampleId);
    final done = info.slots.where((s) => plates.any(s.matches)).length;
    final res = info.analyse(plates, store.rule);
    final details = [
      if (info.condition.isNotEmpty) info.condition,
      if (info.timeH != null) hoursLabel(info.timeH!),
      store.hasPlan(info.sampleId)
          ? '$done/${info.slots.length} plates'
          : '${plates.length} plate${plates.length == 1 ? '' : 's'}',
    ];
    return ListTile(
      title: Text(info.sampleId),
      subtitle: Text('${details.join(' · ')}\n${resultSummary(res)}'),
      isThreeLine: true,
      trailing: Text(
        sciValue(res.stats.mean),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              SampleDetailScreen(store: store, sampleId: info.sampleId),
        ),
      ),
    );
  }
}

class SampleDetailScreen extends StatelessWidget {
  const SampleDetailScreen({
    super.key,
    required this.store,
    required this.sampleId,
  });

  final PlateStore store;
  final String sampleId;

  String _slotLabel(SampleInfo info, Slot s) => [
    if (s.dilutionExp != null) dilutionLabel(s.dilutionExp!),
    if (s.replicate != null) 'R${s.replicate}',
    if (s.dilutionExp == null && s.replicate == null) 'plate',
  ].join(' · ');

  Future<void> _shoot(
    BuildContext context,
    SampleInfo info,
    Slot slot, {
    bool gallery = false,
  }) => countNewPlate(
    context,
    store,
    fromGallery: gallery,
    preset: PlatePreset(info: info, slot: slot),
  );

  Future<void> _printLabels(BuildContext context, SampleInfo info) async {
    final regular = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
    final bold = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
    final pdf = await buildLabelSheet(
      labelsForSample(info),
      fontData: regular,
      boldFontData: bold,
    );
    final safe = info.sampleId.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    await shareBytes(
      pdf,
      'labels_$safe.pdf',
      'application/pdf',
      subject: 'Plate labels for ${info.sampleId}',
    );
  }

  Future<void> _delete(BuildContext context, SampleInfo info) async {
    final plates = store.platesOf(info.sampleId).length;
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${info.sampleId}?'),
        content: Text(
          plates == 0
              ? 'The sample plan will be removed.'
              : 'Remove only the plan and keep its $plates plate${plates == 1 ? '' : 's'}, '
                    'or delete the plates too?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          if (plates > 0)
            TextButton(
              onPressed: () => Navigator.pop(context, 'plan'),
              child: const Text('Keep plates'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'all'),
            child: Text(plates > 0 ? 'Delete all' : 'Delete'),
          ),
        ],
      ),
    );
    if (choice == null) return;
    await store.deleteSample(info.sampleId, withPlates: choice == 'all');
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final info = store.sampleInfo(sampleId);
        final plates = store.platesOf(sampleId)
          ..sort(
            (a, b) => a.dilutionExp != b.dilutionExp
                ? a.dilutionExp.compareTo(b.dilutionExp)
                : a.replicate.compareTo(b.replicate),
          );
        final planned = store.hasPlan(sampleId);
        final next = planned ? info.nextSlot(plates) : null;
        final t = Theme.of(context).textTheme;
        return Scaffold(
          appBar: AppBar(
            title: Text(sampleId),
            actions: [
              PopupMenuButton<String>(
                onSelected: (v) => switch (v) {
                  'edit' => openSampleSetup(context, store, edit: info),
                  'copy' => openSampleSetup(context, store, template: info),
                  'labels' => _printLabels(context, info),
                  _ => _delete(context, info),
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: Text(planned ? 'Edit plan' : 'Create plan'),
                  ),
                  const PopupMenuItem(
                    value: 'copy',
                    child: Text('New sample like this'),
                  ),
                  if (planned)
                    const PopupMenuItem(
                      value: 'labels',
                      child: Text('Print plate labels (PDF)'),
                    ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete sample'),
                  ),
                ],
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _ResultCard(store: store, info: info, plates: plates),
              const SizedBox(height: 16),
              if (planned) ...[
                Text('Plates', style: t.titleMedium),
                const SizedBox(height: 4),
                Text(
                  [
                    info.method.label,
                    if (info.isDrop)
                      '${fixed(info.dropVolumeUl, 0)} µL drops'
                    else
                      '${info.volumeMl} mL per plate',
                    if (info.isDrop) info.dropLayout.label,
                  ].join(' · '),
                  style: t.bodySmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final slot in info.slots)
                      _SlotChip(
                        label: _slotLabel(info, slot),
                        plate: plates.where(slot.matches).firstOrNull,
                        isNext: identical(slot, next),
                        onShoot: () => _shoot(context, info, slot),
                        onOpen: (p) => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                ReviewScreen(store: store, record: p),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (next != null)
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _shoot(context, info, next),
                          icon: const Icon(Icons.camera_alt_outlined),
                          label: Text('Photograph ${_slotLabel(info, next)}'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.outlined(
                        tooltip: 'Import photo for ${_slotLabel(info, next)}',
                        onPressed: () =>
                            _shoot(context, info, next, gallery: true),
                        icon: const Icon(Icons.photo_library_outlined),
                      ),
                    ],
                  )
                else
                  Text('All planned plates are done.', style: t.bodyMedium),
              ] else ...[
                Text(
                  'This sample has no plan (its plates were saved one by one). '
                  'Use “Create plan” in the menu for a guided plate list.',
                  style: t.bodySmall,
                ),
                const SizedBox(height: 8),
                for (final p in plates) RecordTile(store: store, record: p),
              ],
              _DetailsSection(info: info),
            ],
          ),
        );
      },
    );
  }
}

class _SlotChip extends StatelessWidget {
  const _SlotChip({
    required this.label,
    required this.plate,
    required this.isNext,
    required this.onShoot,
    required this.onOpen,
  });

  final String label;
  final PlateRecord? plate;
  final bool isNext;
  final VoidCallback onShoot;
  final void Function(PlateRecord) onOpen;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = plate;
    if (p == null) {
      return ActionChip(
        avatar: Icon(
          Icons.camera_alt_outlined,
          size: 18,
          color: isNext ? cs.primary : null,
        ),
        label: Text(label),
        side: isNext ? BorderSide(color: cs.primary, width: 2) : null,
        onPressed: onShoot,
      );
    }
    final warn = p.spreader || p.tntc;
    return ActionChip(
      avatar: Icon(
        warn ? Icons.warning_amber_rounded : Icons.check_circle,
        size: 18,
        color: warn ? cs.error : cs.primary,
      ),
      label: Text('$label: ${p.count}'),
      backgroundColor: cs.secondaryContainer,
      onPressed: () => onOpen(p),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.store,
    required this.info,
    required this.plates,
  });

  final PlateStore store;
  final SampleInfo info;
  final List<PlateRecord> plates;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final rule = info.ruleFor(store.rule);
    final res = info.analyse(plates, store.rule);
    final s = res.stats;
    final details = [
      if (info.experiment.isNotEmpty) info.experiment,
      if (info.condition.isNotEmpty) info.condition,
      if (info.timeH != null) hoursLabel(info.timeH!),
    ];
    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (details.isNotEmpty)
              Text(details.join(' · '), style: t.labelLarge),
            const SizedBox(height: 4),
            Text(
              s.n == 0
                  ? 'No countable plates yet'
                  : '${sciValue(s.mean)} CFU/mL',
              style: t.headlineSmall,
            ),
            if (s.n > 0) ...[
              const SizedBox(height: 4),
              Text(
                [
                  if (s.n > 1) 'SD ${sciValue(s.sd)}',
                  if (s.n > 1) 'CV ${fixed(s.cvPercent, 1)} %',
                  'n = ${s.n} replicate${s.n == 1 ? '' : 's'}',
                ].join(' · '),
                style: t.bodyMedium,
              ),
              const SizedBox(height: 2),
              Text(
                'log₁₀ CFU/mL ${fixed(s.log10Mean)}'
                '${s.n > 1 ? ' ± ${fixed(s.log10Sd)}' : ''}',
                style: t.titleMedium,
              ),
            ],
            const SizedBox(height: 8),
            for (final e in res.perReplicate.entries)
              Text(
                'R${e.key}: ${prettySci(e.value.toString())}'
                '${e.value.note.isNotEmpty ? ' — ${e.value.note}' : ''}',
                style: t.bodySmall,
              ),
            const SizedBox(height: 8),
            Text(
              'Each replicate pools its countable ${info.isDrop ? 'drops' : 'plates'} '
              '(${rule.min}–${rule.max} colonies, ${rule.label}) as ΣC / Σ(V × d); '
              'log₁₀ is the mean ± SD of the replicates\' log values.',
              style: t.bodySmall,
            ),
            if (!info.isDrop) ...[
              const SizedBox(height: 8),
              SegmentedButton<CountingRule>(
                showSelectedIcon: false,
                segments: [
                  for (final r in CountingRule.spreadRules)
                    ButtonSegment(value: r, label: Text(r.label)),
                ],
                selected: {store.rule},
                onSelectionChanged: (sel) => store.setRule(sel.first),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Experiment details and notes, when any are set.
class _DetailsSection extends StatelessWidget {
  const _DetailsSection({required this.info});

  final SampleInfo info;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final rows = [
      ('Strain', info.strain),
      (
        'Medium',
        [
          info.medium,
          if (info.mediumBatch.isNotEmpty) 'batch ${info.mediumBatch}',
        ].where((e) => e.isNotEmpty).join(', '),
      ),
      (
        'Incubation',
        [
          if (info.incubationH != null) hoursLabel(info.incubationH!),
          if (info.incubationTempC != null)
            '${fixed(info.incubationTempC!, info.incubationTempC! % 1 == 0 ? 0 : 1)} °C',
        ].join(' at '),
      ),
      ('Operator', info.operator),
      ('Tags', info.tags.join(', ')),
      ('Notes', info.notes),
    ].where((r) => r.$2.isNotEmpty).toList();
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Details', style: t.titleMedium),
          const SizedBox(height: 6),
          for (final (k, v) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 96, child: Text(k, style: t.bodySmall)),
                  Expanded(child: Text(v, style: t.bodyMedium)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
