import 'package:flutter/material.dart';

import '../core/calculator.dart';
import '../data/plate_record.dart';
import '../data/plate_store.dart';
import 'format.dart';
import 'review_screen.dart';

/// Samples (plates grouped by sample ID) with their pooled CFU/mL.
class SamplesScreen extends StatelessWidget {
  const SamplesScreen({super.key, required this.store});

  final PlateStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final samples = store.samples();
        return Scaffold(
          appBar: AppBar(title: const Text('Samples')),
          body: samples.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Give plates a sample ID when saving them; plates of the same sample '
                      'are combined here into one CFU/mL value.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView(
                  children: [
                    for (final e in samples.entries)
                      _SampleTile(
                        store: store,
                        sampleId: e.key,
                        plates: e.value,
                      ),
                  ],
                ),
        );
      },
    );
  }
}

class _SampleTile extends StatelessWidget {
  const _SampleTile({
    required this.store,
    required this.sampleId,
    required this.plates,
  });

  final PlateStore store;
  final String sampleId;
  final List<PlateRecord> plates;

  @override
  Widget build(BuildContext context) {
    final est = estimate([
      for (final p in plates) p.toPlateCount(),
    ], rule: store.rule);
    return ListTile(
      title: Text(sampleId),
      subtitle: Text('${plates.length} plate${plates.length == 1 ? '' : 's'}'),
      trailing: Text(
        prettySci(est.toString()),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SampleDetailScreen(store: store, sampleId: sampleId),
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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final t = Theme.of(context).textTheme;
        final plates = [...?store.samples()[sampleId]]
          ..sort(
            (a, b) => a.dilutionExp != b.dilutionExp
                ? a.dilutionExp.compareTo(b.dilutionExp)
                : a.createdAt.compareTo(b.createdAt),
          );
        final counts = [for (final p in plates) p.toPlateCount()];
        final est = estimate(counts, rule: store.rule);
        final used = est.platesUsed.toSet();

        return Scaffold(
          appBar: AppBar(title: Text(sampleId)),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card.filled(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Pooled estimate', style: t.labelLarge),
                      const SizedBox(height: 4),
                      Text(prettySci(est.toString()), style: t.headlineMedium),
                      if (est.note.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(est.note, style: t.bodyMedium),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        'N = ΣC / Σ(V × d) over plates with ${store.rule.min}–${store.rule.max} '
                        'colonies (${store.rule.label}); rounded to 2 significant figures.',
                        style: t.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<CountingRule>(
                showSelectedIcon: false,
                segments: [
                  for (final r in CountingRule.values)
                    ButtonSegment(value: r, label: Text(r.label)),
                ],
                selected: {store.rule},
                onSelectionChanged: (s) => store.setRule(s.first),
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < plates.length; i++)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    used.contains(counts[i])
                        ? Icons.check_circle
                        : Icons.remove_circle_outline,
                    color: used.contains(counts[i])
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  title: Text(
                    '${dilutionLabel(plates[i].dilutionExp)} · ${plates[i].volumeMl} mL',
                  ),
                  subtitle: Text(
                    [
                      shortDate(plates[i].createdAt),
                      if (plates[i].spreader) 'spreader',
                      if (plates[i].tntc) 'TNTC',
                    ].join(' · '),
                  ),
                  trailing: Text('${plates[i].count}', style: t.titleLarge),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          ReviewScreen(store: store, record: plates[i]),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
