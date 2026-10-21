import 'dart:io';

import 'package:colony_counter/core/plate.dart';
import 'package:colony_counter/core/zones.dart';
import 'package:colony_counter/data/plate_store.dart';
import 'package:colony_counter/data/sample_info.dart';
import 'package:colony_counter/data/storage/storage.dart';
import 'package:colony_counter/data/zone_record.dart';
import 'package:colony_counter/l10n/l10n.dart';
import 'package:colony_counter/main.dart';
import 'package:colony_counter/ui/multi_plate_screen.dart';
import 'package:colony_counter/ui/photo_flow.dart';
import 'package:colony_counter/ui/review_layout.dart';
import 'package:colony_counter/ui/review_screen.dart';
import 'package:colony_counter/ui/zone_review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'synth.dart';

// Regression tests for layout bugs on tablet and desktop screens.

Future<void> _settleReal(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 300 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
  }
}

Future<void> _loaded(WidgetTester tester) => _settleReal(
  tester,
  () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
);

/// The app's bundled fonts, so text is as wide as on a device.
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
  await family('ColonySymbols', ['$a/ColonySymbols-Regular.ttf']);
}

Future<void> _screen(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.runAsync(_loadFonts);
}

Widget _app(Widget home) =>
    MaterialApp(theme: appTheme(Brightness.light), home: home);

/// A plain photo [w] × [h] px, re-encoded from [fixture].
Uint8List _small(String fixture, int w, int h) => img.encodeJpg(
  img.copyResize(
    img.decodeJpg(File('test/fixtures/$fixture.jpg').readAsBytesSync())!,
    width: w,
    height: h,
  ),
);

/// The photo as drawn on screen.
Rect _photoRect(WidgetTester tester) => tester.getRect(
  find
      .descendant(
        of: find.byType(InteractiveViewer),
        matching: find.byType(Image),
      )
      .first,
);

/// The photo fills its area: as wide or as tall as the area allows.
void _fills(WidgetTester tester, double aspect) {
  final area = tester.getRect(find.byType(InteractiveViewer));
  final photo = _photoRect(tester);
  final fit = area.width / area.height < aspect
      ? area.width
      : area.height * aspect;
  expect(photo.width, moreOrLessEquals(fit, epsilon: 1));
  expect(area.contains(photo.center), isTrue);
}

void main() {
  group('review side panel uses the full height', () {
    final drops = SampleInfo(
      sampleId: 'D1',
      method: PlatingMethod.drop,
      dilutions: const [3, 4, 5, 6, 7, 8, 9, 10],
      replicates: 1,
      dropLayout: DropLayout.dilutions,
      dropArrangement: DropArrangement.sectors,
    );
    final film = SampleInfo(
      sampleId: 'F1',
      method: PlatingMethod.film,
      format: PlateFormat.filmAc,
      dilutions: const [1],
      replicates: 1,
      volumeMl: 1,
    );
    for (final size in [const Size(960, 600), const Size(1280, 800)]) {
      for (final (info, fixture) in [
        (drops, 'drops_sectors8'),
        (film, 'film_ac_crowded'),
      ]) {
        testWidgets('${info.method.name} at ${size.width}x${size.height}', (
          tester,
        ) async {
          await _screen(tester, size);
          final store = PlateStore(MemoryStorage());
          await tester.runAsync(store.load);
          await tester.runAsync(() => store.upsertSample(info));
          await tester.pumpWidget(
            _app(
              ReviewScreen(
                store: store,
                photo: File('test/fixtures/$fixture.jpg').readAsBytesSync(),
                preset: PlatePreset(info: info, slot: info.slots.first),
              ),
            ),
          );
          await _loaded(tester);
          final panel = tester.getRect(find.byType(ReviewDetails));
          final photo = tester.getRect(find.byType(InteractiveViewer));
          expect(panel.left, greaterThanOrEqualTo(photo.right));
          // The details are not squeezed into a small scroller of their
          // own (40 % of the screen height, as on a phone).
          final details = tester.state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(ReviewDetails),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          expect(details.position.maxScrollExtent, 0);
          expect(find.text(tr.reviewSavePlate), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('a photo with fewer pixels than its area fills it', () {
    for (final size in [const Size(800, 1280), const Size(600, 960)]) {
      final at = '${size.width.toInt()}x${size.height.toInt()}';
      testWidgets('review at $at, and a tap removes the colony under it', (
        tester,
      ) async {
        await _screen(tester, size);
        final plate = SynthPlate(
          250,
          250,
          220,
          colonies: 6,
          fixed: [(250, 250)],
        );
        final photo = synthPhoto(500, 500, [plate]);
        final store = PlateStore(MemoryStorage());
        await tester.runAsync(store.load);
        await tester.pumpWidget(_app(ReviewScreen(store: store, photo: photo)));
        await _loaded(tester);
        _fills(tester, 1);

        int count() => int.parse(
          tester
              .widget<Text>(
                find.byWidgetPredicate(
                  (w) => w is Text && w.style?.fontSize == 36,
                ),
              )
              .data!,
        );
        final before = count();
        final edit = find.text(tr.reviewModeEdit);
        await tester.ensureVisible(edit);
        await tester.pumpAndSettle();
        await tester.tap(edit);
        await tester.pumpAndSettle();
        // 12 screen px beside the middle colony: within the 16 screen px
        // a tap may miss by.
        final r = _photoRect(tester);
        await tester.tapAt(
          r.topLeft +
              const Offset(250, 250) * (r.width / 500) +
              const Offset(12, 0),
        );
        await tester.pumpAndSettle();
        expect(count(), before - 1);
      });

      testWidgets('zone review at $at', (tester) async {
        await _screen(tester, size);
        final photo = _small('zones_reflected', 500, 500);
        final measured = measureZonesInPhoto((photo, const ZoneOptions()));
        final r = ZoneRecord.fromResult(
          measured,
          id: 'p1',
          imagePath: 'zone_p1.jpg',
          createdAt: DateTime(2026, 10, 9),
        );
        expect(r.imageWidth, 500);
        final store = PlateStore(MemoryStorage());
        await tester.runAsync(() async {
          await store.load();
          await store.savePhoto(photo, 'zone_p1');
          await store.upsertZone(r);
        });
        await tester.pumpWidget(
          _app(ZoneReviewScreen(store: store, record: r)),
        );
        await _loaded(tester);
        await tester.pumpAndSettle();
        _fills(tester, 1);
      });

      testWidgets('found plates at $at', (tester) async {
        await _screen(tester, size);
        final photo = _small('multi_six_gap10', 450, 312);
        final store = PlateStore(MemoryStorage());
        await tester.runAsync(store.load);
        await tester.pumpWidget(
          _app(MultiPlateScreen(store: store, photo: photo)),
        );
        await _loaded(tester);
        _fills(tester, 450 / 312);
      });
    }
  });

  testWidgets('dialogs are at most 560 wide on a wide screen', (tester) async {
    await _screen(tester, const Size(1280, 800));
    final long =
        'A long explanation that would otherwise run across the '
            'whole screen. ' *
        8;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Alert'),
                      content: Text(long),
                    ),
                  ),
                  child: const Text('alert'),
                ),
                TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => SimpleDialog(
                      title: const Text('Simple'),
                      children: [Text(long)],
                    ),
                  ),
                  child: const Text('simple'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    for (final (button, type) in [
      ('alert', AlertDialog),
      ('simple', SimpleDialog),
    ]) {
      await tester.tap(find.text(button));
      await tester.pumpAndSettle();
      final dialog = tester.getRect(
        find
            .descendant(of: find.byType(type), matching: find.byType(Material))
            .first,
      );
      expect(dialog.width, lessThanOrEqualTo(560), reason: button);
      expect(dialog.width, greaterThanOrEqualTo(280), reason: button);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
    }
  });
}
