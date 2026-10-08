import 'package:colony_counter/core/calculator.dart';
import 'package:colony_counter/core/classical.dart';
import 'package:colony_counter/core/drop_stats.dart';
import 'package:colony_counter/core/plate.dart';
import 'package:colony_counter/core/spots.dart';
import 'package:colony_counter/data/drop_results.dart';
import 'package:colony_counter/data/export.dart';
import 'package:colony_counter/data/plate_record.dart';
import 'package:colony_counter/data/plate_store.dart';
import 'package:colony_counter/data/sample_info.dart';
import 'package:colony_counter/data/storage/storage.dart';
import 'package:colony_counter/l10n/labels.dart';
import 'package:colony_counter/ui/samples_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A drop plate whose drops hold [counts] colonies: (dilution, count) per
/// drop, laid out in a row 100 px apart.
PlateRecord _plate(
  String id,
  List<(int, int)> counts, {
  int replicate = 1,
  bool spreader = false,
  Set<int> excluded = const {},
  Set<int> tntc = const {},
  Set<int> crowded = const {},
  List<String> flags = const [],
}) {
  final spots = <Spot>[];
  final colonies = <Colony>[];
  for (var i = 0; i < counts.length; i++) {
    final (d, n) = counts[i];
    final x = 100.0 + 100 * i, y = 500.0;
    spots.add(
      Spot(
        x,
        y,
        40,
        dilutionExp: d,
        replicate: replicate,
        tntc: tntc.contains(i),
        excluded: excluded.contains(i) ? DropExclusion.bubble : null,
        flags: [if (crowded.contains(i)) 'crowded'],
      ),
    );
    for (var k = 0; k < n; k++) {
      colonies.add(Colony(x - 20 + k % 6 * 7, y - 20 + k ~/ 6 * 7, 2));
    }
  }
  return PlateRecord(
    id: id,
    createdAt: DateTime(2026, 10, 8),
    imagePath: '$id.jpg',
    imageWidth: 1000,
    imageHeight: 1000,
    plate: const Plate(500, 500, 450),
    colonies: colonies,
    autoCount: colonies.length,
    flags: flags,
    sampleId: 'D',
    volumeMl: 0.01,
    replicate: replicate,
    spreader: spreader,
    spots: spots,
  );
}

SampleInfo _info({
  DropMode mode = DropMode.pooled,
  (int, int) window = kDropWindow,
  int perDilution = 3,
}) => SampleInfo(
  sampleId: 'D',
  method: PlatingMethod.drop,
  dilutions: const [4, 5, 6],
  replicates: 2,
  dropLayout: DropLayout.dilutions,
  dropArrangement: DropArrangement.grid,
  dropsPerDilution: perDilution,
  dropMode: mode,
  dropWindow: window,
);

const _series = [
  (4, 40),
  (4, 45),
  (4, 38),
  (5, 20),
  (5, 25),
  (5, 15),
  (6, 3),
  (6, 2),
  (6, 1),
];

void main() {
  group('Drop results', () {
    test('mode and window round-trip; older samples are pooled 3–30', () {
      final info = _info(mode: DropMode.first, window: (5, 50));
      final back = SampleInfo.fromJson(info.toJson());
      expect(back.dropMode, DropMode.first);
      expect(back.dropWindow, (5, 50));
      final old = SampleInfo.fromJson({'sample_id': 'O', 'method': 'drop'});
      expect(old.dropMode, DropMode.pooled);
      expect(old.dropWindow, kDropWindow);
      final bad = SampleInfo.fromJson({
        ...info.toJson(),
        'drop_window': [30, 3],
      });
      expect(bad.dropWindow, kDropWindow);
    });

    test('pooled and first countable dilution, per replicate', () {
      final plates = [_plate('a', _series)];
      final pooled = _info().analyse(plates, CountingRule.fdaBam);
      // In-window drops: 20, 25, 15 at 10⁻⁵ and 3 at 10⁻⁶.
      expect(
        pooled.perReplicate[1]!.value,
        closeTo(roundSig(63 / (3 * 0.01e-5 + 0.01e-6)), 1),
      );
      final first = _info(mode: DropMode.first)
          .analyse(plates, CountingRule.fdaBam);
      expect(first.perReplicate[1]!.value, closeTo(2e8, 1));
      expect(first.perReplicate[1]!.qualifier, Qualifier.exact);
    });

    test('the sample window is used, and named in notes', () {
      final plates = [_plate('a', _series)];
      // 5–50: 40, 45, 38 at 10⁻⁴ come into the window, 3 at 10⁻⁶ drops out.
      final res = _info(
        mode: DropMode.first,
        window: (5, 50),
      ).analyse(plates, CountingRule.fdaBam);
      expect(res.perReplicate[1]!.value, closeTo(roundSig(41 / 0.01e-4), 1));
      final low = _info(window: (5, 50)).analyse([
        _plate('b', const [(6, 1), (6, 2), (6, 0)]),
      ], CountingRule.fdaBam).perReplicate[1]!;
      expect(low.qualifier, Qualifier.estimated);
      expect(estimateNote(low), contains('5–50'));
    });

    test('left-out drops and spreader plates are not counted', () {
      final plates = [
        _plate('a', const [(5, 20), (5, 60), (5, 22)], excluded: {1}),
      ];
      final s = dropSummary(_info(), plates);
      expect(s.rows.single.counts, [20, 22]);
      expect(s.rows.single.excluded, 1);
      expect(s.excluded, 1);
      final spread = dropSummary(_info(), [
        _plate('b', const [(5, 20)], spreader: true),
      ]);
      expect(spread.rows.single.counts, isEmpty);
    });

    test('summary: interval, drops used and warnings', () {
      final plates = [
        _plate('a', _series, replicate: 1),
        _plate(
          'b',
          const [
            (4, 40),
            (4, 41),
            (4, 39),
            (5, 6),
            (5, 30),
            (5, 7),
            (6, 2),
            (6, 1),
            (6, 0),
          ],
          replicate: 2,
          crowded: {4},
        ),
      ];
      final s = dropSummary(_info(), plates);
      expect(s.rows.map((r) => r.dilutionExp), [4, 5, 6]);
      expect(s.rows[1].counts, hasLength(6));
      expect(s.estimate.qualifier, 'exact');
      expect(s.estimate.dilutionsUsed, [5, 6]);
      expect(s.estimate.low, lessThan(s.estimate.cfuPerMl));
      expect(s.estimate.high, greaterThan(s.estimate.cfuPerMl));
      expect(s.warnings, containsAll(['overdispersed', 'crowded_drops']));
      expect(s.warnings, isNot(contains('drops_not_as_planned')));
      expect(s.planned, 18);
      expect(s.found, 18);

      final short = dropSummary(_info(), [
        _plate('c', _series.take(8).toList(), flags: ['layout_uncertain']),
      ]);
      expect(
        short.warnings,
        containsAll(['drops_not_as_planned', 'layout_uncertain']),
      );
    });

    test('a plate alone uses the sample window and mode', () {
      final p = _plate('a', _series);
      final e = p.estimateAlone(
        CountingRule.fdaBam,
        dropMode: DropMode.first,
        dropWindow: kDropWindow,
      );
      expect(e.value, closeTo(2e8, 1));
    });
  });

  group('Drop exports', () {
    test('plates, samples and drops CSV', () async {
      final store = PlateStore(MemoryStorage());
      await store.load();
      await store.upsertSample(_info());
      await store.upsert(_plate('a', _series, excluded: {8}));

      final plates = platesCsv(store).trim().split('\n');
      final ph = plates.first.split(',');
      final pr = plates[1].split(',');
      String col(String name) => pr[ph.indexOf(name)];
      expect(col('drop_layout'), 'grid');
      expect(col('drop_mode'), 'pooled');
      expect(col('drop_window'), '3-30');
      expect(col('drops_planned'), '9');
      expect(col('drops_found'), '9');
      expect(col('drops_excluded'), '1');

      final samples = samplesCsv(store).trim().split('\n');
      final sh = samples.first.split(',');
      final sr = samples[1].split(',');
      String scol(String name) => sr[sh.indexOf(name)];
      expect(scol('drop_dilution_used'), '1e-5;1e-6');
      expect(double.parse(scol('drop_mean')), closeTo(20, 1e-9));
      expect(double.parse(scol('drop_vmr')), closeTo(25 / 20, 1e-9));
      expect(double.parse(scol('cfu_ci_low')), lessThan(2e8));
      expect(double.parse(scol('cfu_ci_high')), greaterThan(2e8));

      final drops = dropsCsv(store).trim().split('\n');
      expect(drops, hasLength(10));
      final dh = drops.first.split(',');
      final last = drops.last.split(',');
      expect(last[dh.indexOf('dilution')], '1e-6');
      expect(last[dh.indexOf('count')], '1');
      expect(last[dh.indexOf('excluded')], 'true');
      expect(last[dh.indexOf('exclusion_reason')], 'bubble');
    });
  });

  testWidgets('sample card shows the drop table and its interval', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final store = PlateStore(MemoryStorage());
    await tester.runAsync(store.load);
    await tester.runAsync(() => store.upsertSample(_info()));
    await tester.runAsync(() => store.upsert(_plate('a', _series)));
    await tester.pumpWidget(
      MaterialApp(
        home: SampleDetailScreen(store: store, sampleId: 'D'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Drops per dilution'), findsOneWidget);
    expect(
      find.text('10⁻⁵ · 20 25 15 · mean 20.0 ± 5.0 · VMR 1.25'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Pooled from 10⁻⁵, 10⁻⁶ (4 drops)'),
      findsOneWidget,
    );
    expect(find.textContaining('95 % CI'), findsOneWidget);
    expect(
      find.textContaining('Pooled · 3–30 colonies per drop'),
      findsOneWidget,
    );
  });
}
