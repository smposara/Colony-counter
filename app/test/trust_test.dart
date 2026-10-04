import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:colony_counter/core/calculator.dart';
import 'package:colony_counter/core/classical.dart';
import 'package:colony_counter/core/pipeline.dart';
import 'package:colony_counter/core/plate.dart';
import 'package:colony_counter/data/accuracy.dart';
import 'package:colony_counter/data/export.dart';
import 'package:colony_counter/data/plate_record.dart';
import 'package:colony_counter/data/plate_store.dart';
import 'package:colony_counter/data/sample_info.dart';
import 'package:colony_counter/data/storage/storage.dart';
import 'package:colony_counter/data/training_export.dart';
import 'package:colony_counter/ui/accuracy_screen.dart';
import 'package:colony_counter/ui/multi_plate_screen.dart';
import 'package:colony_counter/ui/timelapse_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'synth.dart';

var _n = 0;

PlateRecord _rec({
  String sample = 'S1',
  int auto = 100,
  List<Colony>? colonies,
  bool verified = false,
  List<Colony> rejected = const [],
  List<String> flags = const [],
  PlateFormat format = PlateFormat.dish90,
  double volumeMl = 0.1,
  int dilutionExp = 4,
  String seriesId = '',
  double? hours,
  String? id,
}) {
  _n++;
  return PlateRecord(
    id: id ?? 'r$_n',
    createdAt: DateTime(2026, 10, 4, 8, _n),
    imagePath: 'r$_n.jpg',
    imageWidth: 1000,
    imageHeight: 1000,
    plate: const Plate(500, 500, 450),
    colonies:
        colonies ?? [for (var i = 0; i < auto; i++) Colony(100.0 + i, 500, 5)],
    autoCount: auto,
    sampleId: sample,
    dilutionExp: dilutionExp,
    volumeMl: volumeMl,
    verified: verified,
    rejected: rejected,
    flags: flags,
    format: format,
    seriesId: seriesId,
    incubationH: hours,
  );
}

List<Colony> _cols(int auto, {int manual = 0}) => [
  for (var i = 0; i < auto; i++) Colony(100.0 + i, 500, 5),
  for (var i = 0; i < manual; i++) Colony(100.0 + i, 600, 5, manual: true),
];

void main() {
  test('new record fields survive JSON', () {
    final r = _rec(
      verified: true,
      rejected: const [Colony(1, 2, 3)],
      format: PlateFormat.square100,
      seriesId: 'x',
      hours: 24,
    );
    final back = PlateRecord.fromJson(r.toJson());
    expect(back.verified, isTrue);
    expect(back.rejected.single.x, 1);
    expect(back.format, PlateFormat.square100);
    expect(back.seriesId, 'x');
    expect(back.incubationH, 24);
    const sq = Plate(
      10,
      20,
      30,
      shape: PlateShape.square,
      angle: 0.1,
      diameterMm: 100,
    );
    final p = Plate.fromJson(sq.toJson());
    expect((p.isSquare, p.angle, p.diameterMm), (true, 0.1, 100));
    const flat = Plate(10, 20, 30, shape: PlateShape.square);
    expect(flat.contains(10 + 25, 20 + 25), isTrue); // near a corner
    expect(flat.contains(10 + 29.5, 20 + 29.5), isFalse); // rounded corner
    expect(flat.contains(10 + 29.5, 20), isTrue);
    expect(const Plate(10, 20, 30).contains(10 + 29, 20 + 29), isFalse);
  });

  test('accuracy report scores the automatic count against checked plates', () {
    final report = AccuracyReport([
      // App 100, checked 110: missed 10 → −9.1 %.
      _rec(auto: 100, colonies: _cols(100, manual: 10), verified: true),
      // App 50, user removed 5 → checked 45: +11.1 %, flagged.
      _rec(
        auto: 50,
        colonies: _cols(45),
        rejected: [for (var i = 0; i < 5; i++) const Colony(1, 1, 3)],
        verified: true,
        flags: const ['low_contrast'],
      ),
      _rec(auto: 200, colonies: _cols(200), verified: true),
      _rec(auto: 80, colonies: _cols(10)), // not checked: ignored
    ]);
    final s = report.all;
    expect(s.n, 3);
    expect(s.meanAbsPercent, closeTo((100 / 11 + 100 / 9 + 0) / 3, 1e-9));
    expect(s.within10Percent, closeTo(200 / 3, 1e-9));
    expect(s.precision, closeTo(345 / 350 * 100, 1e-9));
    expect(s.recall, closeTo(345 / 355 * 100, 1e-9));
    final (warned, rest) = report.byWarning;
    expect((warned.n, rest.n), (1, 2));
    expect(report.byRange['30–300']!.n, 3);
  });

  test('confidence warnings flag crowded and faint plates', () {
    final det = Detection(
      [for (var i = 0; i < 300; i++) Colony(i.toDouble(), 0, 3, score: 5)],
      4,
      1,
      0.1,
      0,
    );
    const plate = Plate(500, 500, 450); // 90 mm, 0.1 mm/px
    final mask = plate.mask(1000, 1000);
    final w = confidenceWarnings(det, plate, mask);
    expect(w, containsAll(['crowded', 'low_contrast']));
    expect(w, isNot(contains('many_clusters')));
  });

  test('membrane samples: CFU/100 mL and the membrane counting range', () {
    final info = SampleInfo(
      sampleId: 'Tap',
      method: PlatingMethod.membrane,
      format: PlateFormat.membrane47,
      dilutions: const [0],
      replicates: 1,
      volumeMl: 100,
      membraneRule: CountingRule.membrane80,
    );
    final back = SampleInfo.fromJson(info.toJson());
    expect(back.isMembrane, isTrue);
    expect(back.membraneRule, CountingRule.membrane80);
    expect(back.unitLabel, 'CFU/100 mL');
    final plate = _rec(
      sample: 'Tap',
      auto: 42,
      format: PlateFormat.membrane47,
      volumeMl: 100,
      dilutionExp: 0,
    );
    final res = back.analyse([plate], CountingRule.fdaBam);
    expect(res.rule, CountingRule.membrane80);
    // 42 colonies in 100 mL = 0.42 CFU/mL = 42 CFU/100 mL.
    expect(res.stats.mean * back.unitFactor, closeTo(42, 1e-9));
    expect(
      plate
          .estimateAlone(CountingRule.fdaBam)
          .describe(factor: 100, unit: 'CFU/100 mL'),
      '4.2 × 10^1 CFU/100 mL',
    );
  });

  test('only the latest photo of a time-lapse counts towards CFU/mL', () {
    final info = SampleInfo(
      sampleId: 'S1',
      dilutions: const [4],
      replicates: 1,
    );
    final early = _rec(auto: 20, seriesId: 'a', hours: 16);
    final late = _rec(auto: 60, seriesId: 'a', hours: 48);
    expect(latestOfSeries([late, early]), [late]);
    final res = info.analyse([early, late], CountingRule.fdaBam);
    expect(res.stats.mean, closeTo(60 / (0.1 * 1e-4), 1e-3));
  });

  test('training export: COCO, YOLO and rejected marks', () async {
    final store = PlateStore(MemoryStorage());
    await store.load();
    final photo = Uint8List.fromList(
      img.encodeJpg(img.Image(width: 1000, height: 1000)),
    );
    Future<void> add(PlateRecord r) async {
      final name = await store.savePhoto(photo, r.id);
      await store.upsert(PlateRecord.fromJson({...r.toJson(), 'image': name}));
    }

    await add(
      _rec(
        auto: 3,
        colonies: const [
          Colony(100, 200, 10),
          Colony(300, 300, 10, n: 2),
          Colony(500, 500, 8, manual: true),
        ],
        rejected: const [Colony(700, 700, 6)],
        verified: true,
      ),
    );
    await add(_rec(auto: 5)); // uncorrected
    expect(trainingPlates(store, TrainingSelection.checked).length, 1);
    expect(trainingPlates(store, TrainingSelection.all).length, 2);

    final zip = await buildTrainingExport(
      store,
      selection: TrainingSelection.checked,
    );
    final archive = ZipDecoder().decodeBytes(zip);
    final coco = jsonDecode(
      utf8.decode(archive.findFile('annotations.json')!.content as List<int>),
    ) as Map;
    expect((coco['images'] as List).single['checked'], isTrue);
    final anns = coco['annotations'] as List;
    expect(anns.length, 3);
    expect(anns.map((a) => a['category_id']), [1, 2, 1]);
    expect(anns.map((a) => a['source']), ['auto', 'auto', 'manual']);
    expect((coco['rejected'] as List).length, 1);
    final id = (coco['images'] as List).single['plate_id'];
    final yolo = utf8
        .decode(archive.findFile('labels/$id.txt')!.content as List<int>)
        .trim()
        .split('\n');
    expect(yolo.first, '0 0.100000 0.200000 0.022000 0.022000');
    expect(archive.findFile('images/$id.jpg'), isNotNull);
  });

  test('CSV columns for plate type, checks and time-lapse', () async {
    final store = PlateStore(MemoryStorage());
    await store.load();
    await store.upsert(
      _rec(
        verified: true,
        seriesId: 's',
        hours: 24,
        rejected: const [Colony(1, 1, 1, n: 2)],
      ),
    );
    final lines = platesCsv(store).trim().split('\n');
    final row = Map.fromIterables(lines[0].split(','), lines[1].split(','));
    expect(row['plate_type'], 'dish90');
    expect(row['checked_by_hand'], 'true');
    expect(row['auto_removed'], '2');
    expect(row['incubation_h'], '24.0');
    expect(row['timelapse_series'], 's');
  });

  test('find and crop several plates in a photo', () {
    final plates = [
      SynthPlate(300, 300, 220, colonies: 15),
      SynthPlate(820, 300, 220, colonies: 25),
    ];
    final bytes = synthPhoto(1150, 620, plates, seed: 9);
    final found = findPlatesInPhoto((bytes, PlateFormat.dish90));
    expect((found.width, found.height), (1150, 620));
    expect(found.plates.length, 2);
    expect(found.plates[1].cx, closeTo(820, 10));
    final (crop, inCrop) = cropToPlate((bytes, found.plates[1]));
    final res = countPhoto(crop, CountOptions(plate: inCrop));
    expect(res.count, inInclusiveRange(23, 27));
  });

  group('screens', () {
    void tall(WidgetTester tester) {
      tester.view.physicalSize = const Size(1080, 6000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
    }

    testWidgets('accuracy screen summarises checked plates', (tester) async {
      tall(tester);
      final store = PlateStore(MemoryStorage());
      await tester.runAsync(() async {
        await store.load();
        await store.upsert(
          _rec(auto: 100, colonies: _cols(100, manual: 10), verified: true),
        );
        await store.upsert(_rec(auto: 50, colonies: _cols(50), verified: true));
      });
      await tester.pumpWidget(MaterialApp(home: AccuracyScreen(store: store)));
      await tester.pump();
      expect(find.text('100 % of plates within ±10 %'), findsOneWidget);
      expect(find.text('Checked plates'), findsOneWidget);
      expect(find.text('app 100 · checked 110\n-9.1 %'), findsOneWidget);
    });

    testWidgets('time-lapse screen shows colonies appearing', (tester) async {
      tall(tester);
      final store = PlateStore(MemoryStorage());
      await tester.runAsync(() async {
        await store.load();
        await store.upsert(
          _rec(
            id: 'a',
            colonies: const [Colony(600, 500, 4)],
            seriesId: 'a',
            hours: 16,
          ),
        );
        await store.upsert(
          _rec(
            colonies: const [Colony(600, 500, 8), Colony(300, 300, 4)],
            seriesId: 'a',
            hours: 24,
          ),
        );
      });
      await tester.pumpWidget(
        MaterialApp(
          home: TimelapseScreen(store: store, seriesId: 'a'),
        ),
      );
      await tester.pump();
      expect(find.text('2 colonies at 24 h'), findsOneWidget);
      expect(
        find.textContaining('1 appeared after the first photo'),
        findsOneWidget,
      );
      expect(find.text('Colonies counted over time'), findsOneWidget);
    });

    testWidgets('multi-plate screen finds the plates and labels them by plan', (
      tester,
    ) async {
      tall(tester);
      final store = PlateStore(MemoryStorage());
      final info = SampleInfo(
        sampleId: 'S9',
        dilutions: const [4, 5],
        replicates: 1,
      );
      await tester.runAsync(() async {
        await store.load();
        await store.upsertSample(info);
      });
      final bytes = synthPhoto(1150, 620, [
        SynthPlate(300, 300, 220, colonies: 15),
        SynthPlate(820, 300, 220, colonies: 25),
      ], seed: 9);
      await tester.pumpWidget(
        MaterialApp(
          home: MultiPlateScreen(store: store, photo: bytes, info: info),
        ),
      );
      for (
        var i = 0;
        i < 100 && find.text('2 plates found').evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }
      expect(find.text('2 plates found'), findsOneWidget);
      expect(find.text('1: 10⁻⁴ · R1'), findsOneWidget);
      expect(find.text('2: 10⁻⁵ · R1'), findsOneWidget);
    });
  });
}
