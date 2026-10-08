import 'package:colony_counter/core/classical.dart';
import 'package:colony_counter/core/drop_layout.dart';
import 'package:colony_counter/core/plate.dart';
import 'package:colony_counter/core/spots.dart';
import 'package:colony_counter/data/accuracy.dart';
import 'package:colony_counter/data/plate_record.dart';
import 'package:colony_counter/data/sample_info.dart';
import 'package:flutter_test/flutter_test.dart';

PlateRecord _plate(
  List<Spot> spots,
  List<Colony> colonies, {
  bool spreader = false,
  bool verified = false,
}) => PlateRecord(
  id: 'p',
  createdAt: DateTime(2026, 10, 8),
  imagePath: 'p.jpg',
  imageWidth: 1000,
  imageHeight: 1000,
  plate: const Plate(500, 500, 450),
  colonies: colonies,
  autoCount: colonies.length,
  sampleId: 'D',
  volumeMl: 0.01,
  spreader: spreader,
  verified: verified,
  spots: spots,
);

List<Colony> _around(double x, double y, int n) => [
  for (var i = 0; i < n; i++) Colony(x + i % 4 * 6, y + i ~/ 4 * 6, 2),
];

void main() {
  group('Spot', () {
    test('new fields round-trip through JSON', () {
      const s = Spot(
        10,
        20,
        30,
        dilutionExp: 5,
        replicate: 2,
        position: 3,
        excluded: DropExclusion.bubble,
        flags: ['crowded'],
      );
      final back = Spot.fromJson(s.toJson());
      expect(back.position, 3);
      expect(back.excluded, DropExclusion.bubble);
      expect(back.isExcluded, isTrue);
      expect(back.flags, ['crowded']);
      expect(back.dilutionExp, 5);
      expect(back.replicate, 2);
    });

    test('older drops load unchanged', () {
      final s = Spot.fromJson({'cx': 1, 'cy': 2, 'r': 3, 'd': 4, 'rep': 1});
      expect(s.position, isNull);
      expect(s.isExcluded, isFalse);
      expect(s.flags, isEmpty);
      expect(s.toJson().keys, containsAll(['cx', 'cy', 'r', 'd', 'rep']));
      expect(s.toJson().containsKey('excluded'), isFalse);
    });

    test('copyWith can include a drop again', () {
      const s = Spot(0, 0, 1, excluded: DropExclusion.splash);
      expect(s.copyWith(include: true).isExcluded, isFalse);
      expect(s.copyWith(replicate: 2).isExcluded, isTrue);
    });
  });

  group('Sample drop layout', () {
    test('round-trips, and older samples are free', () {
      final info = SampleInfo(
        sampleId: 'D',
        method: PlatingMethod.drop,
        dilutions: const [4, 5, 6],
        dropLayout: DropLayout.dilutions,
        dropArrangement: DropArrangement.grid,
        dropsPerDilution: 3,
        dropPitchMm: 12.5,
      );
      final back = SampleInfo.fromJson(info.toJson());
      expect(back.dropArrangement, DropArrangement.grid);
      expect(back.dropsPerDilution, 3);
      expect(back.dropPitchMm, 12.5);
      final old = SampleInfo.fromJson({
        'sample_id': 'O',
        'method': 'drop',
        'dilutions': [4, 5],
      });
      expect(old.dropArrangement, DropArrangement.free);
      expect(old.dropTemplate, isA<FreeTemplate>());
    });

    test('templates follow the plan', () {
      final rows = SampleInfo(
        sampleId: 'D',
        method: PlatingMethod.drop,
        dilutions: const [4, 5, 6, 7],
        replicates: 2,
        dropLayout: DropLayout.dilutions,
        dropArrangement: DropArrangement.grid,
        dropsPerDilution: 3,
        dropPitchMm: 12,
      );
      final g = rows.dropTemplate as GridTemplate;
      expect((g.rows, g.cols, g.pitchMm), (4, 3, 12.0));
      expect(rows.dropsPerPlate, 12);
      expect(rows.dropDilutions(rows.slots.first), [4, 5, 6, 7]);

      final ring = SampleInfo(
        sampleId: 'R',
        method: PlatingMethod.drop,
        dilutions: const [4, 5, 6],
        replicates: 5,
        dropArrangement: DropArrangement.sectors,
      );
      final t = ring.dropTemplate as SectorTemplate;
      expect(t.n, 5); // one dilution per plate: its 5 replicate drops
      expect(t.ringMm, closeTo(0.28 * 90, 1e-9));
      expect(ring.dropDilutions(ring.slots[1]), [5]);
      final pos = templatePositionsMm(t, ring.dropDilutions(ring.slots[1]));
      expect({for (final p in pos) p.dilutionExp}, {5});

      final row = SampleInfo(
        sampleId: 'W',
        method: PlatingMethod.drop,
        replicates: 4,
        dropArrangement: DropArrangement.grid,
      );
      final gr = row.dropTemplate as GridTemplate;
      expect((gr.rows, gr.cols), (1, 4));
    });

    test('labels do not wrap round: extra drops are flagged', () {
      final reps = SampleInfo(
        sampleId: 'D',
        method: PlatingMethod.drop,
        dilutions: const [4, 5],
        replicates: 3,
      );
      final slot = reps.slots.first;
      expect(reps.dropLabel(slot, 2).replicate, 3);
      expect(reps.dropLabel(slot, 2).unplanned, isFalse);
      final extra = reps.dropLabel(slot, 3);
      expect(extra.replicate, 4); // was 1 (wrapped) before
      expect(extra.unplanned, isTrue);

      final dils = SampleInfo(
        sampleId: 'E',
        method: PlatingMethod.drop,
        dilutions: const [4, 5, 6],
        replicates: 2,
        dropLayout: DropLayout.dilutions,
        dropsPerDilution: 2,
      );
      final s2 = dils.slots[1];
      expect(
        [for (var i = 0; i < 6; i++) dils.dropLabel(s2, i).dilutionExp],
        [4, 4, 5, 5, 6, 6],
      );
      expect(dils.dropLabel(s2, 0).replicate, 2);
      expect(dils.dropLabel(s2, 6).dilutionExp, 6);
      expect(dils.dropLabel(s2, 6).unplanned, isTrue);
    });

    test('the layout of older drop plates is inferred from their drops', () {
      final mixed = _plate(const [
        Spot(100, 100, 40, dilutionExp: 4),
        Spot(300, 100, 40, dilutionExp: 4),
        Spot(100, 300, 40, dilutionExp: 5),
        Spot(300, 300, 40, dilutionExp: 5),
      ], const []);
      final info = SampleInfo.inferred('D', [mixed]);
      expect(info.isDrop, isTrue);
      expect(info.dropLayout, DropLayout.dilutions);
      expect(info.dilutions, [4, 5]);
      expect(info.dropsPerDilution, 2);
      expect(info.dropVolumeUl, closeTo(10, 1e-9));

      final reps = _plate(const [
        Spot(100, 100, 40, dilutionExp: 6, replicate: 1),
        Spot(300, 100, 40, dilutionExp: 6, replicate: 2),
        Spot(500, 100, 40, dilutionExp: 6, replicate: 3),
      ], const []);
      final r = SampleInfo.inferred('D', [reps]);
      expect(r.dropLayout, DropLayout.replicates);
      expect(r.dilutions, [6]);
      expect(r.replicates, 3);
    });
  });

  group('Drops in results', () {
    test('left-out drops do not count; a spreader affects every drop', () {
      final spots = [
        const Spot(100, 100, 40, dilutionExp: 5, replicate: 1),
        const Spot(
          300,
          100,
          40,
          dilutionExp: 5,
          replicate: 2,
          excluded: DropExclusion.merged,
        ),
      ];
      final cols = [..._around(90, 90, 12), ..._around(290, 90, 25)];
      final obs = _plate(spots, cols).observations();
      expect(obs, hasLength(1));
      expect(obs.single.count.count, 12);
      final spread = _plate(spots, cols, spreader: true).observations();
      expect(spread.single.count.spreader, isTrue);
    });

    test('checked drop plates join the accuracy check', () {
      final p = _plate(
        const [Spot(100, 100, 40, dilutionExp: 5)],
        _around(90, 90, 5),
        verified: true,
      );
      expect(AccuracyReport([p]).points, hasLength(1));
    });

    test('a crowded drop counted by area keeps the difference on a mark', () {
      final cols = [
        const Colony(100, 100, 4),
        const Colony(110, 100, 6),
        const Colony(300, 100, 3),
      ];
      final res = DropPlateResult(
        plate: const Plate(500, 500, 450),
        drops: [
          FoundDrop(
            x: 105,
            y: 100,
            radiusPx: 40,
            position: 0,
            dilutionExp: 4,
            replicate: 1,
            count: 9,
            crowded: true,
            colonies: const [0, 1],
          ),
          FoundDrop(
            x: 300,
            y: 100,
            radiusPx: 40,
            position: 1,
            dilutionExp: 5,
            replicate: 1,
            count: 1,
            colonies: const [2],
          ),
        ],
        colonies: cols,
        strays: const [],
        fit: null,
        flags: const [],
      );
      final (marks, spots) = res.toSpots();
      expect(marks[1].n, 8); // the larger mark carries the 7 merged colonies
      expect(marks[0].n, 1);
      expect(countInSpot(spots[0], marks), 9);
      expect(countInSpot(spots[1], marks), 1);
      expect(spots[0].flags, ['crowded']);
      expect(spots[0].position, 0);
      expect(spots[0].radius, closeTo(40 * kAssignRadius, 1e-9));
    });
  });
}
