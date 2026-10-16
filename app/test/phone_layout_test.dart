import 'dart:io';

import 'package:colony_counter/core/plate.dart';
import 'package:colony_counter/data/plate_store.dart';
import 'package:colony_counter/data/sample_info.dart';
import 'package:colony_counter/data/storage/storage.dart';
import 'package:colony_counter/l10n/l10n.dart';
import 'package:colony_counter/main.dart';
import 'package:colony_counter/ui/photo_flow.dart';
import 'package:colony_counter/ui/review_screen.dart';
import 'package:colony_counter/ui/sample_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _settleReal(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 300 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
  }
}

/// The app's bundled fonts, so text is as wide as on a phone (the test font
/// draws every letter as a wide square).
Future<void> _loadFonts() async {
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final f in files) {
      loader.addFont(
        Future.value(ByteData.sublistView(File(f).readAsBytesSync())),
      );
    }
    await loader.load();
  }

  const a = 'assets/fonts';
  await family('Roboto', [
    '$a/Roboto-Regular.ttf',
    '$a/Roboto-Medium.ttf',
    '$a/Roboto-Bold.ttf',
  ]);
  await family('IBMPlexSansThai', [
    '$a/IBMPlexSansThai-Regular.ttf',
    '$a/IBMPlexSansThai-Medium.ttf',
    '$a/IBMPlexSansThai-Bold.ttf',
  ]);
  await family('ColonySymbols', ['$a/ColonySymbols-Regular.ttf']);
}

/// A 360 × 780 phone in [language].
Future<void> _phone(WidgetTester tester, String language) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.runAsync(_loadFonts);
  setCurrentStrings(lookupAppLocalizations(Locale(language)));
  addTearDown(
    () => setCurrentStrings(lookupAppLocalizations(const Locale('en'))),
  );
}

Widget _app(Widget home) =>
    MaterialApp(theme: appTheme(Brightness.light), home: home);

/// [f] lies wholly inside the screen and the visible part of every scroll
/// view around it.
void _fullyVisible(WidgetTester tester, Finder f) {
  final rect = tester.getRect(f);
  final screen = Offset.zero & tester.view.physicalSize / 3;
  expect(screen.contains(rect.topLeft), isTrue, reason: '$f on screen');
  expect(screen.contains(rect.bottomRight - const Offset(1, 1)), isTrue);
  for (final s
      in find.ancestor(of: f, matching: find.byType(Scrollable)).evaluate()) {
    final view = tester.getRect(find.byWidget(s.widget));
    expect(rect.top, greaterThanOrEqualTo(view.top - 0.5), reason: '$f top');
    expect(
      rect.bottom,
      lessThanOrEqualTo(view.bottom + 0.5),
      reason: '$f bottom',
    );
  }
}

/// The text [label] is on one line: as wide as it needs, and inside the
/// button around it.
void _oneLine(WidgetTester tester, String label) {
  final f = find.text(label);
  expect(f, findsOneWidget, reason: label);
  final p = tester.renderObject<RenderParagraph>(f);
  expect(
    p.size.width,
    greaterThanOrEqualTo(p.getMaxIntrinsicWidth(double.infinity) - 0.5),
    reason: '"$label" wraps',
  );
  expect(p.didExceedMaxLines, isFalse, reason: '"$label" is cut off');
  final button = tester.getRect(
    find.ancestor(of: f, matching: find.byType(TextButton)).first,
  );
  final r = tester.getRect(f);
  expect(r.left, greaterThanOrEqualTo(button.left), reason: label);
  expect(r.right, lessThanOrEqualTo(button.right), reason: label);
}

void main() {
  for (final language in ['en', 'th']) {
    testWidgets('$language: crowded plate keeps the count and hint in view', (
      tester,
    ) async {
      await _phone(tester, language);
      final store = PlateStore(MemoryStorage());
      await tester.runAsync(store.load);
      store.accuracyCheckEvery = 1;
      await tester.pumpWidget(
        _app(
          ReviewScreen(
            store: store,
            photo: File('test/fixtures/dense.jpg').readAsBytesSync(),
          ),
        ),
      );
      await _settleReal(
        tester,
        () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
      );
      // Both banners, a chip, and the Edit hint.
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(find.text(tr.reviewAccuracyCheck), findsOneWidget);
      expect(find.byType(Chip), findsWidgets);
      final edit = find.text(tr.reviewModeEdit);
      await tester.ensureVisible(edit);
      await tester.pumpAndSettle();
      await tester.tap(edit);
      await tester.pumpAndSettle();

      final count = find.byWidgetPredicate(
        (w) => w is Text && w.style?.fontSize == 36,
      );
      expect(count, findsOneWidget);
      _fullyVisible(tester, count);
      _fullyVisible(tester, find.text(tr.reviewHintEdit));
      // The photo keeps a usable size.
      expect(
        tester.getSize(find.byType(InteractiveViewer)).height,
        greaterThan(250),
      );

      // A long banner opens in full when tapped.
      final banner = find.text(tr.reviewAccuracyCheck);
      bool cut() =>
          tester.renderObject<RenderParagraph>(banner).didExceedMaxLines;
      expect(cut(), isTrue);
      await tester.tap(banner);
      await tester.pumpAndSettle();
      expect(cut(), isFalse);
    });

    testWidgets('$language: EB film mode buttons do not break words', (
      tester,
    ) async {
      await _phone(tester, language);
      final store = PlateStore(MemoryStorage());
      await tester.runAsync(store.load);
      final info = SampleInfo(
        sampleId: 'F1',
        method: PlatingMethod.film,
        format: PlateFormat.filmEb,
        dilutions: const [1],
        replicates: 1,
        volumeMl: 1,
      );
      await tester.runAsync(() => store.upsertSample(info));
      await tester.pumpWidget(
        _app(
          ReviewScreen(
            store: store,
            photo: File('test/fixtures/film_eb.jpg').readAsBytesSync(),
            preset: PlatePreset(info: info, slot: info.slots.first),
          ),
        ),
      );
      await _settleReal(
        tester,
        () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
      );
      for (final m in [
        tr.reviewModeZoom,
        tr.reviewModeEdit,
        tr.reviewModePlate,
        tr.reviewModeKind,
        tr.reviewModeGas,
        tr.reviewModeYellow,
      ]) {
        _oneLine(tester, m);
      }
    });

    testWidgets('$language: plating buttons do not break words', (
      tester,
    ) async {
      await _phone(tester, language);
      final store = PlateStore(MemoryStorage());
      await tester.runAsync(store.load);
      await tester.pumpWidget(_app(SampleSetupScreen(store: store)));
      await tester.pumpAndSettle();
      for (final m in [
        tr.setupSpread,
        tr.setupDrop,
        tr.setupMembrane,
        tr.setupFilm,
      ]) {
        _oneLine(tester, m);
      }
    });
  }
}
