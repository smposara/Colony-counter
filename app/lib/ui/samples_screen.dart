import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/calculator.dart';
import '../core/labels.dart';
import '../core/plate.dart';
import '../core/stats.dart';
import '../data/plate_record.dart';
import '../data/label_sheet.dart';
import '../data/plate_store.dart';
import '../data/sample_info.dart';
import '../l10n/l10n.dart';
import '../l10n/labels.dart';
import 'format.dart';
import 'home_screen.dart';
import 'insets.dart';
import 'multi_plate_screen.dart';
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
        title: Text(tr.samplesNotFoundTitle(label.sampleId)),
        content: Text(tr.samplesSetUpNow),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr.samplesCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr.samplesSetUp),
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
        content: Text(tr.samplesPhotographNow),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr.samplesJustOpen),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr.samplesPhotograph),
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
      SnackBar(content: Text(tr.samplesAlreadyCounted(label.caption))),
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
/// "log₁₀ 6.12 ± 0.05 (n = 3)", in [info]'s unit (CFU/mL, CFU/g or
/// CFU/100 mL).
String resultSummary(SampleResult r, SampleInfo info) {
  final s = r.stats;
  if (s.n == 0) return tr.samplesNoResult;
  final sd = s.n > 1 ? ' ± ${fixed(s.log10Sd)}' : '';
  final log = s.log10Mean + math.log(info.unitFactor) / math.ln10;
  return 'log₁₀ ${fixed(log)}$sd (n = ${s.n})${r.qualified ? ' · ${tr.samplesEstimated}' : ''}';
}

/// Mean of [r] in the sample's unit with its qualifier: "< 10" or "> …" when
/// every replicate is a bound, "est." when any replicate is an estimate.
String qualifiedMean(SampleResult r, SampleInfo info) {
  final s = r.stats;
  if (s.n == 0) return '—';
  // Only the replicates the mean is made from (as ReplicateStats).
  final q = {
    for (final e in r.perReplicate.values)
      if (e.value.isFinite && e.value > 0) e.qualifier,
  };
  final v = sciValue(s.mean * info.unitFactor);
  if (q.length == 1 && q.first == Qualifier.lessThan) return '< $v';
  if (q.length == 1 && q.first == Qualifier.greaterThan) return '> $v';
  return r.qualified ? '$v ${tr.samplesEstimated}' : v;
}

String hoursLabel(double h) => tr.samplesHours(fixed(h, h % 1 == 0 ? 0 : 1));

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
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(tr.samplesEmpty, textAlign: TextAlign.center),
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
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: tr.samplesSearchHint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            if (samples.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(tr.samplesNoMatch, textAlign: TextAlign.center),
              ),
            for (final name in names) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(
                  name.isEmpty ? tr.samplesNoExperiment : name,
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
          ? tr.samplesPlatesDone(done, info.slots.length)
          : tr.samplesPlateCount(plates.length),
    ];
    // A dry film also lists its other results (e.g. coliforms beside E. coli).
    final film = [
      for (final k in info.filmResults)
        '${filmResultText(k)} '
            '${qualifiedMean(info.analyse(plates, store.rule, result: k), info)}',
    ];
    return ListTile(
      title: Text(info.sampleId),
      subtitle: Text(
        '${details.join(' · ')}\n'
        '${film.length > 1 ? film.join(' · ') : resultSummary(res, info)}',
      ),
      isThreeLine: true,
      trailing: Text(
        sciValue(res.stats.mean * info.unitFactor),
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
    if (s.dilutionExp == null && s.replicate == null) tr.samplesSlotPlate,
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
    final thai = await rootBundle.load(
      'assets/fonts/IBMPlexSansThai-Regular.ttf',
    );
    final thaiBold = await rootBundle.load(
      'assets/fonts/IBMPlexSansThai-Bold.ttf',
    );
    final pdf = await buildLabelSheet(
      labelsForSample(info),
      fontData: regular,
      boldFontData: bold,
      thaiFontData: thai,
      thaiBoldFontData: thaiBold,
    );
    final safe = info.sampleId.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    await shareBytes(
      pdf,
      'labels_$safe.pdf',
      'application/pdf',
      subject: tr.samplesLabelsSubject(info.sampleId),
    );
  }

  Future<void> _delete(BuildContext context, SampleInfo info) async {
    final plates = store.platesOf(info.sampleId).length;
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr.samplesDeleteTitle(info.sampleId)),
        content: Text(
          plates == 0 ? tr.samplesDeletePlanOnly : tr.samplesDeleteAsk(plates),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr.samplesCancel),
          ),
          if (plates > 0)
            TextButton(
              onPressed: () => Navigator.pop(context, 'plan'),
              child: Text(tr.samplesKeepPlates),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'all'),
            child: Text(plates > 0 ? tr.samplesDeleteAll : tr.samplesDelete),
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
        final plates = latestOfSeries(store.platesOf(sampleId))
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
                  'multi' => countSeveralPlates(context, store, info: info),
                  _ => _delete(context, info),
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: Text(
                      planned ? tr.samplesEditPlan : tr.samplesCreatePlan,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'copy',
                    child: Text(tr.samplesNewLikeThis),
                  ),
                  // One film per photo: the multi-plate finder is for dishes.
                  if (next != null && !info.isFilm)
                    PopupMenuItem(value: 'multi', child: Text(tr.samplesMulti)),
                  if (planned)
                    PopupMenuItem(
                      value: 'labels',
                      child: Text(tr.samplesPrintLabels),
                    ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(tr.samplesDeleteSample),
                  ),
                ],
              ),
            ],
          ),
          body: ListView(
            padding: scrollPadding(
              context,
              const EdgeInsets.fromLTRB(16, 8, 16, 32),
            ),
            children: [
              _ResultCard(store: store, info: info, plates: plates),
              const SizedBox(height: 16),
              if (planned) ...[
                Text(tr.samplesPlates, style: t.titleMedium),
                const SizedBox(height: 4),
                Text(
                  [
                    info.method.text,
                    if (info.isDrop)
                      tr.samplesDropsUl(fixed(info.dropVolumeUl, 0))
                    else if (info.isMembrane)
                      tr.samplesMlFiltered(
                        fixed(info.volumeMl, info.volumeMl % 1 == 0 ? 0 : 1),
                      )
                    else
                      tr.samplesMlPerPlate('${info.volumeMl}'),
                    if (!info.isMembrane &&
                        !info.isFilm &&
                        info.format != PlateFormat.dish90)
                      info.format.text,
                    if (info.isFilm) info.format.text,
                    if (info.isDrop) info.dropLayout.text,
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
                          label: Text(
                            tr.samplesPhotographSlot(_slotLabel(info, next)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.outlined(
                        tooltip: tr.samplesImportFor(_slotLabel(info, next)),
                        onPressed: () =>
                            _shoot(context, info, next, gallery: true),
                        icon: const Icon(Icons.photo_library_outlined),
                      ),
                    ],
                  )
                else
                  Text(tr.samplesAllDone, style: t.bodyMedium),
              ] else ...[
                Text(tr.samplesNoPlan, style: t.bodySmall),
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
    final f = info.unitFactor, unit = info.unitLabel;
    final logShift = math.log(f) / math.ln10;
    // One block per result: a dry film reports each (E. coli, coliforms…).
    final results = info.filmResults.isEmpty
        ? const <String?>[null]
        : info.filmResults;
    List<Widget> block(String? result) {
      final res = info.analyse(plates, store.rule, result: result);
      final s = res.stats;
      return [
        if (result != null) ...[
          const SizedBox(height: 8),
          Text(filmResultText(result), style: t.titleSmall),
        ],
        const SizedBox(height: 4),
        Text(
          s.n == 0 ? tr.samplesNoCountable : '${sciValue(s.mean * f)} $unit',
          style: t.headlineSmall,
        ),
        if (s.n > 0) ...[
          const SizedBox(height: 4),
          Text(
            [
              if (s.n > 1) 'SD ${sciValue(s.sd * f)}',
              if (s.n > 1) 'CV ${fixed(s.cvPercent, 1)} %',
              tr.samplesReplicateCount(s.n),
            ].join(' · '),
            style: t.bodyMedium,
          ),
          const SizedBox(height: 2),
          Text(
            'log₁₀ $unit ${fixed(s.log10Mean + logShift)}'
            '${s.n > 1 ? ' ± ${fixed(s.log10Sd)}' : ''}',
            style: t.titleMedium,
          ),
        ],
        const SizedBox(height: 8),
        for (final e in res.perReplicate.entries)
          Text(
            'R${e.key}: ${prettySci(estimateText(e.value, factor: f, unit: unit))}'
            '${e.value.note.isNotEmpty ? ' — ${estimateNote(e.value)}' : ''}',
            style: t.bodySmall,
          ),
      ];
    }

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
            for (final k in results) ...block(k),
            const SizedBox(height: 8),
            Text(
              (info.isDrop
                  ? tr.samplesPoolDrops
                  : info.isMembrane
                  ? tr.samplesPoolFilters
                  : tr.samplesPoolPlates)('${rule.min}–${rule.max}', rule.text),
              style: t.bodySmall,
            ),
            if (!info.isDrop && !info.isMembrane && !info.isFilm) ...[
              const SizedBox(height: 8),
              SegmentedButton<CountingRule>(
                showSelectedIcon: false,
                segments: [
                  for (final r in CountingRule.spreadRules)
                    ButtonSegment(value: r, label: Text(r.text)),
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
      (tr.samplesStrain, info.strain),
      (
        tr.samplesMedium,
        [
          info.medium,
          if (info.mediumBatch.isNotEmpty) tr.samplesBatch(info.mediumBatch),
        ].where((e) => e.isNotEmpty).join(', '),
      ),
      (
        tr.samplesIncubation,
        switch ((
          info.incubationH == null ? null : hoursLabel(info.incubationH!),
          info.incubationTempC == null
              ? null
              : '${fixed(info.incubationTempC!, info.incubationTempC! % 1 == 0 ? 0 : 1)} °C',
        )) {
          (final h?, final c?) => tr.samplesIncubationAt(h, c),
          (final h?, null) => h,
          (null, final c?) => c,
          (null, null) => '',
        },
      ),
      (tr.samplesOperator, info.operator),
      (tr.samplesTags, info.tags.join(', ')),
      (tr.samplesNotes, info.notes),
    ].where((r) => r.$2.isNotEmpty).toList();
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr.samplesDetails, style: t.titleMedium),
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
