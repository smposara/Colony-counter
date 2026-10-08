import 'dart:convert';
import 'dart:io';

import 'package:colony_counter/core/calculator.dart';
import 'package:colony_counter/core/classical.dart';
import 'package:colony_counter/core/petrifilm.dart';
import 'package:colony_counter/core/plate.dart';
import 'package:colony_counter/data/export.dart';
import 'package:colony_counter/data/plate_record.dart';
import 'package:colony_counter/data/plate_store.dart';
import 'package:colony_counter/data/sample_info.dart';
import 'package:colony_counter/data/storage/storage.dart';
import 'package:colony_counter/ui/format.dart';
import 'package:colony_counter/ui/sample_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A 1 cm grid of 120 px squares over a growth area at (600, 600).
const _grid = FilmGrid(120, 0, 0, 0, 600, 600);
const _area = Plate(600, 600, 303, diameterMm: 50.5);

PlateRecord _film(
  PlateFormat format,
  List<Colony> colonies, {
  String sample = '',
  int dilutionExp = 1,
  String id = '1',
}) => PlateRecord(
  id: id,
  createdAt: DateTime(2026, 10, 8, 9),
  imagePath: '$id.jpg',
  imageWidth: 1200,
  imageHeight: 1500,
  plate: _area,
  colonies: colonies,
  autoCount: colonies.length,
  sampleId: sample,
  dilutionExp: dilutionExp,
  volumeMl: 1,
  format: format,
  filmGrid: _grid,
);

/// EC marks: [blue] blue colonies, [redGas] red with gas, [red] red without.
List<Colony> _ec({int blue = 0, int redGas = 0, int red = 0}) => [
  for (var i = 0; i < blue; i++) Colony(500.0 + i, 600, 4, cls: 1),
  for (var i = 0; i < redGas; i++) Colony(600.0 + i, 600, 4, gas: true),
  for (var i = 0; i < red; i++) Colony(700.0 + i, 600, 4),
];

void main() {
  test('film formats and counting rules', () {
    expect(PlateFormat.films.map((f) => f.film), [
      'ac',
      'ec',
      'cc',
      'eb',
      'ym',
    ]);
    expect(PlateFormat.filmEc.isDish, isFalse);
    expect(PlateFormat.dish90.isDish, isTrue);
    expect(PlateFormat.membrane47.isDish, isFalse);
    expect(filmCountingRule('ac'), CountingRule.filmAc);
    expect(filmCountingRule('ec'), CountingRule.film150);
    expect(filmCountingRule('eb'), CountingRule.film100);
    expect(filmKinds('ym'), ['yeast', 'mold']);
    expect(filmClass('ec', 'blue'), 1);
  });

  test('EC film: E. coli = blue, coliforms = blue + red with gas', () {
    final r = _film(PlateFormat.filmEc, _ec(blue: 12, redGas: 19, red: 5));
    expect(r.filmTally.counts, {'ecoli': 12, 'coliform': 31});
    expect(r.filmTally.estimates, isNull);
    expect(r.filmValue(), 12);
    expect(r.filmValue('coliform'), 31);
    expect(r.estimateAlone(CountingRule.fdaBam).rule, CountingRule.film150);
    // 1 mL of 10⁻¹: 12 → below the 15–150 range, estimated.
    final e = r.estimateAlone(CountingRule.fdaBam);
    expect(e.value, 120);
    expect(e.qualifier, Qualifier.estimated);
    expect(r.estimateAlone(CountingRule.fdaBam, result: 'coliform').value, 310);
  });

  test('above the range: estimate from complete squares × 20 cm²', () {
    // 30 colonies in each of the squares around the centre: well above 250.
    final marks = <Colony>[
      for (var i = -2; i < 2; i++)
        for (var j = -2; j < 2; j++)
          for (var k = 0; k < 30; k++)
            Colony(600 + i * 120 + 10 + k * 3, 600 + j * 120 + 60, 1),
    ];
    final r = _film(PlateFormat.filmAc, marks);
    final t = r.filmTally;
    expect(t.counts['aerobic'], 480);
    expect(t.squaresUsed, greaterThanOrEqualTo(3));
    expect(t.estimates, isNotNull);
    expect(r.filmValue(), t.estimates!['aerobic']);
    expect(filmSummary(r), startsWith('Aerobic count ≈ '));
  });

  test('film records and samples survive JSON; older ones load unchanged', () {
    final r = _film(PlateFormat.filmEb, [
      const Colony(500, 600, 4, gas: true),
      const Colony(520, 600, 4, yellow: true),
      const Colony(540, 600, 4),
    ]);
    final back = PlateRecord.fromJson(
      jsonDecode(jsonEncode(r.toJson())) as Map<String, dynamic>,
    );
    expect(back.format, PlateFormat.filmEb);
    expect(back.filmGrid!.pitchPx, 120);
    expect(back.filmTally.counts, {'enterobacteriaceae': 2});
    expect(
      [for (final c in back.colonies) (c.gas, c.yellow)],
      [(true, false), (false, true), (false, false)],
    );

    final old = PlateRecord.fromJson({
      'id': 'x',
      'created_at': '2026-01-01T00:00:00.000',
      'image': 'x.jpg',
      'image_width': 10,
      'image_height': 10,
      'plate': const Plate(5, 5, 4).toJson(),
      'colonies': [const Colony(1, 1, 1).toJson()],
      'auto_count': 1,
    });
    expect(old.isFilm, isFalse);
    expect(old.filmGrid, isNull);
    expect(old.colonies.single.gas, isFalse);

    final info = SampleInfo(
      sampleId: 'F',
      method: PlatingMethod.film,
      format: PlateFormat.filmYm,
      dilutions: const [1, 2],
      volumeMl: 1,
    );
    final info2 = SampleInfo.fromJson(
      jsonDecode(jsonEncode(info.toJson())) as Map<String, dynamic>,
    );
    expect(info2.isFilm, isTrue);
    expect(info2.filmResults, ['yeast', 'mold']);
    expect(info2.ruleFor(CountingRule.fdaBam), CountingRule.film150);
    expect(
      SampleInfo.inferred('F', [_film(PlateFormat.filmAc, const [])]).method,
      PlatingMethod.film,
    );
  });

  test('CSV export: film columns and one sample row per result', () async {
    final store = PlateStore(MemoryStorage());
    await store.load();
    await store.upsertSample(
      SampleInfo(
        sampleId: 'W1',
        method: PlatingMethod.film,
        format: PlateFormat.filmEc,
        dilutions: const [1],
        replicates: 1,
        volumeMl: 1,
      ),
    );
    await store.upsert(
      _film(
        PlateFormat.filmEc,
        _ec(blue: 20, redGas: 16, red: 3),
        sample: 'W1',
      ),
    );
    final plates = platesCsv(store);
    expect(plates, contains('film_type'));
    expect(plates, contains('ecoli=20;coliform=36'));
    expect(plates, contains(',film,'));
    final samples = samplesCsv(store).trim().split('\n');
    expect(samples.length, 3); // header + E. coli + coliforms
    expect(samples[1], endsWith(',ecoli'));
    expect(samples[2], endsWith(',coliform'));
    final colonies = coloniesCsv(store);
    expect(colonies, contains('gas,yellow_zone'));
    expect(colonies, contains(',blue,'));
  });

  test('formatCount groups thousands', () {
    expect(formatCount(1240.4), '1,240');
    expect(formatCount(999), '999');
    expect(formatCount(1234567), '1,234,567');
  });

  testWidgets('sample setup: Petrifilm method on a 360 dp phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final store = PlateStore(MemoryStorage());
    await tester.runAsync(store.load);
    await tester.pumpWidget(MaterialApp(home: SampleSetupScreen(store: store)));

    await tester.tap(find.text('Film'));
    await tester.pumpAndSettle();
    expect(find.text('Film type'), findsOneWidget);
    expect(find.text('Petrifilm AC (aerobic count)'), findsOneWidget);
    expect(find.textContaining('Counting range 25–250'), findsOneWidget);
    expect(find.text('Colony colours'), findsNothing);

    await tester.tap(find.text('Petrifilm AC (aerobic count)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Petrifilm EC (E. coli/coliform)').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Counting range 15–150'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Sample ID'), 'W2');
    await tester.tap(find.text('Save sample'));
    await tester.pumpAndSettle();
    final info = store.sampleInfo('W2');
    expect(info.method, PlatingMethod.film);
    expect(info.format, PlateFormat.filmEc);
    expect(info.volumeMl, 1);
    expect(info.filmResults, ['ecoli', 'coliform']);
    // A film type does not become the default for dishes.
    expect(store.defaultFormat.isFilm, isFalse);
  });

  test('the Thai strings name every film type', () {
    final th = jsonDecode(
      File('lib/l10n/app_th.arb').readAsStringSync(),
    ) as Map<String, dynamic>;
    for (final k in [
      'formatFilmAc',
      'formatFilmEc',
      'formatFilmCc',
      'formatFilmEb',
      'formatFilmYm',
      'aboutPetrifilm',
    ]) {
      expect(th[k], isA<String>(), reason: k);
    }
  });
}
