import 'dart:convert';
import 'dart:typed_data';

import 'package:colony_counter/core/annotate.dart';
import 'package:colony_counter/core/classical.dart';
import 'package:colony_counter/core/colour.dart';
import 'package:colony_counter/core/labels.dart';
import 'package:colony_counter/core/plate.dart';
import 'package:colony_counter/core/spots.dart';
import 'package:colony_counter/data/export.dart';
import 'package:colony_counter/data/label_sheet.dart';
import 'package:colony_counter/data/plate_record.dart';
import 'package:colony_counter/data/plate_store.dart';
import 'package:colony_counter/data/sample_info.dart';
import 'package:colony_counter/data/storage/storage.dart';
import 'package:colony_counter/ui/samples_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  group('plate labels', () {
    test('payload round trip, including awkward sample IDs', () {
      for (final l in [
        const PlateLabel('Lake-A', dilutionExp: 4, replicate: 2),
        const PlateLabel('S;1=x ทดสอบ', replicate: 3),
        const PlateLabel('D1'),
      ]) {
        final back = PlateLabel.parse(l.encode())!;
        expect(
          (back.sampleId, back.dilutionExp, back.replicate),
          (l.sampleId, l.dilutionExp, l.replicate),
        );
      }
      expect(PlateLabel.parse('https://example.org'), isNull);
      expect(PlateLabel.parse('CC1;d=4'), isNull);
    });

    test('a label QR is read back from a photo-like image', () {
      const label = PlateLabel('Lake-A', dilutionExp: 5, replicate: 1);
      final qr = renderLabelQr(label, moduleSize: 6);
      // Put the code on a grey "bench" with some noise, off-centre, like a photo.
      final photo = img.Image(width: 1400, height: 1000)
        ..clear(img.ColorRgb8(150, 145, 140));
      img.compositeImage(photo, qr, dstX: 700, dstY: 300);
      final jpeg = Uint8List.fromList(img.encodeJpg(photo, quality: 85));
      final read = readLabelFromPhoto(jpeg)!;
      expect(
        (read.sampleId, read.dilutionExp, read.replicate),
        ('Lake-A', 5, 1),
      );
    });

    test('no label in a plain photo', () {
      final blank = img.Image(width: 400, height: 300)
        ..clear(img.ColorRgb8(90, 80, 70));
      expect(
        readLabelFromPhoto(Uint8List.fromList(img.encodePng(blank))),
        isNull,
      );
    });

    test('label sheet PDF has one label per planned plate', () async {
      final info = SampleInfo(
        sampleId: 'Lake-A',
        experiment: 'E',
        dilutions: [4, 5, 6],
        replicates: 3,
      );
      final specs = labelsForSample(info);
      expect(specs.length, 9);
      expect(specs[4].label.caption, 'Lake-A · 10^-5 · R2');
      final pdf = await buildLabelSheet([
        ...specs,
        ...specs,
        ...specs,
      ]); // 27 → 2 pages
      expect(latin1.decode(pdf.sublist(0, 5)), '%PDF-');
      expect(
        RegExp(r'/Type\s*/Page[^s]').allMatches(latin1.decode(pdf)).length,
        2,
      );
    });
  });

  group('experiment details', () {
    final info = SampleInfo(
      sampleId: 'Lake-A',
      experiment: 'Kill curve',
      condition: 'Phage',
      strain: 'E. coli K-12',
      medium: 'Nutrient Agar',
      mediumBatch: 'NA-0923',
      incubationTempC: 37,
      incubationH: 24,
      operator: 'Pim',
      tags: ['pilot', 'lake'],
    );

    test('survive a JSON round trip', () {
      final back = SampleInfo.fromJson(info.toJson());
      expect(back.strain, 'E. coli K-12');
      expect(back.medium, 'Nutrient Agar');
      expect(back.mediumBatch, 'NA-0923');
      expect(back.incubationTempC, 37);
      expect(back.incubationH, 24);
      expect(back.operator, 'Pim');
      expect(back.tags, ['pilot', 'lake']);
      // Older saved samples have none of the fields.
      final old = SampleInfo.fromJson({'sample_id': 'Old'});
      expect((old.strain, old.operator, old.incubationTempC), ('', '', null));
      expect(old.tags, isEmpty);
    });

    test('search matches every word in any field', () {
      expect(info.matches(''), isTrue);
      expect(info.matches('k-12'), isTrue);
      expect(info.matches('pim PILOT'), isTrue);
      expect(info.matches('na-0923 phage'), isTrue);
      expect(info.matches('pim salmonella'), isFalse);
    });

    testWidgets('Samples tab filters by search', (tester) async {
      tester.view.physicalSize = const Size(1080, 6000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final store = PlateStore(MemoryStorage());
      await tester.runAsync(() async {
        await store.load();
        await store.upsertSample(info);
        await store.upsertSample(
          SampleInfo(sampleId: 'River-B', operator: 'Tom', strain: 'S. aureus'),
        );
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SamplesTab(store: store)),
        ),
      );
      await tester.pump();
      expect(find.text('Lake-A'), findsOneWidget);
      expect(find.text('River-B'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'aureus');
      await tester.pump();
      expect(find.text('Lake-A'), findsNothing);
      expect(find.text('River-B'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'nobody');
      await tester.pump();
      expect(find.text('No samples match.'), findsOneWidget);
    });
  });

  group('per-colony export and annotated photo', () {
    // 90 mm dish of radius 450 px → 0.1 mm per px.
    const plate = Plate(500, 500, 450);
    final record = PlateRecord(
      id: 'p1',
      createdAt: DateTime(2026, 10, 4),
      imagePath: 'p1.jpg',
      imageWidth: 1000,
      imageHeight: 1000,
      plate: plate,
      colonies: const [
        Colony(600, 500, 10),
        Colony(500, 300, 5, n: 3),
        Colony(450, 520, 8, manual: true, cls: 1),
      ],
      autoCount: 4,
      sampleId: 'Lake-A',
      dilutionExp: 5,
      replicate: 2,
      colourMode: ColourMode.blueWhite,
    );

    test('colonies CSV has one row per mark, in mm from the centre', () async {
      final store = PlateStore(MemoryStorage());
      await store.load();
      await store.upsert(record);
      final lines = coloniesCsv(store).trim().split('\n');
      expect(lines.length, 4);
      final head = lines.first.split(',');
      expect(head.take(8), [
        'plate_id',
        'sample_id',
        'dilution',
        'replicate',
        'colony',
        'x_mm',
        'y_mm',
        'diameter_mm',
      ]);
      Map<String, String> row(int i) =>
          Map.fromIterables(head, lines[i].split(','));
      expect(row(1)['x_mm'], '10.0');
      expect(row(1)['y_mm'], '0.0');
      expect(row(1)['diameter_mm'], '2.0');
      expect(row(1)['dilution'], '1e-5');
      expect(row(1)['replicate'], '2');
      expect(row(2)['colonies_in_mark'], '3');
      expect(row(2)['y_mm'], '-20.0');
      expect(row(3)['added_by_hand'], 'true');
      expect(row(3)['colour_class_name'], 'Blue');
      expect(row(1)['drop'], '');
      // Median diameter of single, automatic colonies goes in the plate CSV.
      expect(medianDiameterMm(record), 2.0);
    });

    test('annotated photo is a JPEG of the photo with marks and a banner', () {
      final photo = img.Image(width: 1000, height: 1000)
        ..clear(img.ColorRgb8(200, 190, 150));
      final jpeg = annotatePhoto(
        AnnotationJob(
          photo: Uint8List.fromList(img.encodeJpg(photo)),
          plate: plate,
          colonies: record.colonies,
          spots: const [Spot(500, 500, 120)],
          colourMode: ColourMode.blueWhite,
          header: ['Lake-A · 10⁻⁵ · R2', 'Count: 5 · 1.2 × 10⁷ CFU/mL'],
        ),
      );
      final out = img.decodeJpg(jpeg)!;
      expect((out.width, out.height), (1000, 1000));
      // Banner darkens the top; a colony ring is drawn in green at (600±10, 500).
      expect(out.getPixel(500, 5).luminance, lessThan(80));
      final greenRing = [for (var x = 605; x <= 620; x++) out.getPixel(x, 500)]
          .any((p) => p.g - p.r > 80);
      expect(greenRing, isTrue);
      expect(
        asciiOnly('10⁻⁵ · 1.2 × 10⁷ ± 3 µL'),
        '10^-5 - 1.2 x 10^7 +/- 3 uL',
      );
    });
  });
}
