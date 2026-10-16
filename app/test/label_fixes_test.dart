import 'dart:io';
import 'dart:typed_data';

import 'package:colony_counter/core/colour.dart';
import 'package:colony_counter/core/labels.dart';
import 'package:colony_counter/data/label_sheet.dart';
import 'package:colony_counter/data/plate_store.dart';
import 'package:colony_counter/data/sample_info.dart';
import 'package:colony_counter/data/storage/storage.dart';
import 'package:colony_counter/ui/format.dart';
import 'package:colony_counter/ui/photo_flow.dart';
import 'package:colony_counter/ui/review_screen.dart';
import 'package:colony_counter/ui/samples_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';

ByteData _font(String f) =>
    ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync());

Future<String> _tmp() async {
  final dir = await Directory.systemTemp.createTemp('cc_labels');
  addTearDown(() => dir.delete(recursive: true));
  return dir.path;
}

/// Text of [pdf], as poppler's pdftotext reads it.
Future<String> _pdfText(Uint8List pdf) async {
  final dir = await _tmp();
  File('$dir/l.pdf').writeAsBytesSync(pdf);
  final r = await Process.run('pdftotext', ['$dir/l.pdf', '-']);
  expect(r.exitCode, 0, reason: '${r.stderr}');
  return r.stdout as String;
}

Future<void> _settleReal(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 300 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
  }
}

void main() {
  group('label sheet', () {
    test('3 × 8 labels of 70 × 37 mm fill the A4 page', () {
      const mm = PdfPageFormat.mm;
      final a4 = PdfPageFormat.a4;
      for (var i = 0; i < 24; i++) {
        final s = labelSlot(i);
        expect(s.width, closeTo(70 * mm, 1e-6));
        expect(s.height, closeTo(37 * mm, 1e-6));
        expect(s.left, closeTo(i % 3 * 70 * mm, 1e-6));
        expect(s.top, closeTo(0.5 * mm + i ~/ 3 * 37 * mm, 1e-6));
      }
      final last = labelSlot(23);
      expect(last.left + last.width, closeTo(a4.width, 1e-6));
      expect(last.top + last.height, closeTo(a4.height - 0.5 * mm, 1e-6));
    });

    test('the printed page has each QR code in its own label', () async {
      final specs = [
        for (var r = 1; r <= 24; r++)
          LabelSpec(PlateLabel('Lake-A', dilutionExp: 4, replicate: r), ''),
      ];
      final pdf = await buildLabelSheet(specs);
      final dir = await _tmp();
      File('$dir/l.pdf').writeAsBytesSync(pdf);
      const dpi = 150;
      final r = await Process.run('pdftoppm', [
        '-r',
        '$dpi',
        '-png',
        '-singlefile',
        '$dir/l.pdf',
        '$dir/page',
      ]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      final page = img.decodePng(File('$dir/page.png').readAsBytesSync())!;
      final px = dpi / 72;
      for (var i = 0; i < 24; i++) {
        final s = labelSlot(i);
        final crop = img.copyCrop(
          page,
          x: (s.left * px).round(),
          y: (s.top * px).round(),
          width: (s.width * px).floor().clamp(1, page.width - 1),
          height: (s.height * px).floor(),
        );
        final read = readLabelFromPhoto(
          Uint8List.fromList(img.encodePng(crop)),
        );
        expect(read?.replicate, i + 1, reason: 'label $i');
        expect(read?.dilutionExp, 4);
      }
    });

    test('the dilution is printed with superscripts', () async {
      final pdf = await buildLabelSheet(
        [
          const LabelSpec(
            PlateLabel('Lake-A', dilutionExp: 4, replicate: 2),
            '',
          ),
        ],
        fontData: _font('Roboto-Regular.ttf'),
        boldFontData: _font('Roboto-Bold.ttf'),
        symbolFontData: _font('ColonySymbols-Regular.ttf'),
      );
      final text = await _pdfText(pdf);
      expect(text, contains('10⁻⁴'));
      expect(text, isNot(contains('^')));
      // Without a font that has them: a raised "-4", still no caret.
      final plain = await _pdfText(
        await buildLabelSheet([
          const LabelSpec(PlateLabel('Lake-A', dilutionExp: 4), ''),
        ]),
      );
      expect(plain, isNot(contains('^')));
      expect(plain, contains('-4'));
    });
  });

  test('a scanned label caption uses the dilution helper', () {
    expect(
      labelCaption(const PlateLabel('Lake-A', dilutionExp: 5, replicate: 1)),
      'Lake-A · 10⁻⁵ · R1',
    );
    expect(
      labelCaption(const PlateLabel('Lake-A', dilutionExp: 12)),
      'Lake-A · 10⁻¹²',
    );
  });

  group('scanned label', () {
    Future<PlateStore> open(WidgetTester tester, PlateLabel label) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final store = PlateStore(MemoryStorage());
      await tester.runAsync(store.load);
      await tester.runAsync(
        () => store.upsertSample(
          SampleInfo(sampleId: 'Lake-A', dilutions: const [5], replicates: 1),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => openFromLabel(context, store, label),
                child: const Text('scan'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('scan'));
      await tester.pumpAndSettle();
      return store;
    }

    testWidgets('Photograph ends on the sample once the plate is saved', (
      tester,
    ) async {
      final photo = File('test/fixtures/sparse.jpg').readAsBytesSync();
      debugTakePlatePhoto = () async =>
          (bytes: photo, guided: false, camera: '');
      addTearDown(() => debugTakePlatePhoto = null);
      final store = await open(
        tester,
        const PlateLabel('Lake-A', dilutionExp: 5, replicate: 1),
      );
      // The dialog names the plate with a proper superscript.
      expect(find.text('Lake-A · 10⁻⁵ · R1'), findsOneWidget);
      await tester.tap(find.text('Photograph'));
      await tester.pump();
      await _settleReal(
        tester,
        () =>
            find.byType(ReviewScreen).evaluate().isNotEmpty &&
            find.byType(CircularProgressIndicator).evaluate().isEmpty,
      );
      await tester.tap(find.text('Save plate'));
      await tester.pumpAndSettle();
      final save = find.widgetWithText(FilledButton, 'Save');
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await _settleReal(
        tester,
        () => find.byType(SampleDetailScreen).evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();
      expect(store.records, hasLength(1));
      expect(find.byType(ReviewScreen), findsNothing);
      expect(find.byType(SampleDetailScreen), findsOneWidget);
    });

    testWidgets('an already counted plate is named with superscripts', (
      tester,
    ) async {
      final photo = File('test/fixtures/sparse.jpg').readAsBytesSync();
      debugTakePlatePhoto = () async =>
          (bytes: photo, guided: false, camera: '');
      addTearDown(() => debugTakePlatePhoto = null);
      const label = PlateLabel('Lake-A', dilutionExp: 5, replicate: 1);
      final store = await open(tester, label);
      await tester.tap(find.text('Photograph'));
      await tester.pump();
      await _settleReal(
        tester,
        () =>
            find.byType(ReviewScreen).evaluate().isNotEmpty &&
            find.byType(CircularProgressIndicator).evaluate().isEmpty,
      );
      await tester.tap(find.text('Save plate'));
      await tester.pumpAndSettle();
      final save = find.widgetWithText(FilledButton, 'Save');
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await _settleReal(tester, () => store.records.isNotEmpty);
      await tester.pumpAndSettle();
      // Back to the start and scan the same label again.
      Navigator.of(tester.element(find.byType(Scaffold).last))
          .popUntil((r) => r.isFirst);
      await tester.pumpAndSettle();
      await tester.tap(find.text('scan'));
      await tester.pumpAndSettle();
      expect(
        find.text('Lake-A · 10⁻⁵ · R1 is already counted.'),
        findsOneWidget,
      );
    });
  });

  testWidgets('the colour share names the class as elsewhere', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final store = PlateStore(MemoryStorage());
    await tester.runAsync(store.load);
    final info = SampleInfo(
      sampleId: 'C1',
      dilutions: const [5],
      replicates: 1,
      colourMode: ColourMode.twoColours,
    );
    await tester.runAsync(() => store.upsertSample(info));
    await tester.pumpWidget(
      MaterialApp(
        home: ReviewScreen(
          store: store,
          photo: File('test/fixtures/sparse.jpg').readAsBytesSync(),
          preset: PlatePreset(info: info, slot: info.slots.first),
        ),
      ),
    );
    await _settleReal(
      tester,
      () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );
    expect(
      find.textContaining(RegExp(r'^\d+\.\d % Colour B$')),
      findsOneWidget,
    );
    expect(find.textContaining('colour b'), findsNothing);
  });
}
