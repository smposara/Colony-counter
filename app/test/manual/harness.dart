// Screenshots for the user manual (docs/manual/). Not part of the test suite:
// run with `bash test/manual/make_manual.sh`.
//
// Each chapter test drives the real app (ColonyCounterApp) on a phone-sized
// screen, in English and Thai, and saves a PNG per step plus the screen
// rectangles to mark on it (tap here, look here), which
// test/manual/annotate.py turns into numbered callouts.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colony_counter/data/plate_store.dart';
import 'package:colony_counter/data/storage/storage.dart';
import 'package:colony_counter/main.dart';
import 'package:colony_counter/ui/photo_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

/// Phone screen: 360 × 780 logical pixels, saved at 2× (720 × 1560).
/// MANUAL_SIZE=1280x800 renders a tablet or desktop screen instead (the
/// store's tablet and Chromebook screenshots); MANUAL_DPR sets the scale.
final kPhone =
    _size(Platform.environment['MANUAL_SIZE']) ?? const Size(360, 780);
final kDpr = double.tryParse(Platform.environment['MANUAL_DPR'] ?? '') ?? 2.0;

Size? _size(String? s) {
  final m = RegExp(r'^(\d+)x(\d+)$').firstMatch(s ?? '');
  return m == null
      ? null
      : Size(double.parse(m.group(1)!), double.parse(m.group(2)!));
}

final _outDir = Platform.environment['MANUAL_OUT'] ?? 'build/manual';

/// The home screen's tabs: the bottom bar on phones, the rail at the side on
/// wide screens.
final navBar = find.byWidgetPredicate(
  (w) => w is NavigationBar || w is NavigationRail,
);

Uint8List fixture(String name) => File('test/fixtures/$name').readAsBytesSync();

/// What a callout points at.
enum Mark { tap, hold, drag, look, type }

class _Target {
  _Target(this.rect, this.mark);
  final Rect rect;
  final Mark mark;
}

/// The photo the camera or photo picker "returns" next.
Uint8List? nextPhoto;

class _FakePicker extends ImagePickerPlatform {
  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    final p = nextPhoto;
    return p == null ? null : XFile.fromData(p, name: 'photo.jpg');
  }
}

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
  final flutter = Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter';
  await family('MaterialIcons', [
    '$flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ]);
}

/// One chapter in one language.
class Manual {
  Manual(this.tester, this.chapter, this.lang);

  final WidgetTester tester;
  final String chapter;
  final String lang;
  late PlateStore store;
  final _boundary = GlobalKey();
  final _shots = <String, Object>{};

  BuildContext get context => tester.element(find.byType(Navigator).last);
  NavigatorState get navigator =>
      tester.state<NavigatorState>(find.byType(Navigator).first);

  /// Starts the app with an empty store (or [seed]ed).
  Future<void> start({Future<void> Function(PlateStore store)? seed}) async {
    debugDisableShadows = false;
    WidgetsApp.debugAllowBannerOverride = false;
    tester.view.physicalSize = kPhone * kDpr;
    tester.view.devicePixelRatio = kDpr;
    addTearDown(tester.view.reset);
    ImagePickerPlatform.instance = _FakePicker();
    debugTakePlatePhoto = () async {
      final p = nextPhoto;
      return p == null ? null : (bytes: p, guided: true, camera: '0');
    };
    store = PlateStore(MemoryStorage());
    await tester.runAsync(() async {
      await _loadFonts();
      await store.load();
      await store.setDefaults(language: lang, theme: 'light');
      // Chapters start empty: never the first-launch example data.
      await store.setExamplesOffered();
      if (seed != null) await seed(store);
    });
    await tester.pumpWidget(
      RepaintBoundary(
        key: _boundary,
        child: ColonyCounterApp(store: store),
      ),
    );
    await settle();
  }

  /// Pumps until animations end and background work (counting) is done.
  Future<void> settle({bool Function()? until, int seconds = 60}) async {
    for (var i = 0; i < seconds * 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      final busy =
          find.byType(CircularProgressIndicator).evaluate().isNotEmpty ||
          find.byType(LinearProgressIndicator).evaluate().isNotEmpty;
      if ((until?.call() ?? true) && !busy && i > 3) break;
    }
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 20),
    );
  }

  /// Saves the screen as `<chapter>-<name>.<lang>.png` with [marks].
  Future<void> shot(
    String name, [
    List<(Finder, Mark)> marks = const [],
  ]) async {
    // Photos are decoded outside the fake clock.
    await tester.runAsync(() async {
      for (final e in find.byType(Image).evaluate()) {
        await precacheImage((e.widget as Image).image, e);
      }
    });
    await tester.pump();
    final targets = <_Target>[];
    for (final (f, m) in marks) {
      expect(f, findsWidgets, reason: '$chapter/$name');
      // Outline the whole button, not just its label.
      final c = m == Mark.look || m == Mark.drag ? f : control(f);
      // Nearest first; a mark with no button around it outlines itself.
      final hit = c.evaluate().isEmpty ? f.first : c.first;
      targets.add(_Target(tester.getRect(hit), m));
    }
    final file = '$chapter-$name.$lang.png';
    final boundary =
        _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: kDpr);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory(_outDir).createSync(recursive: true);
      File('$_outDir/$file').writeAsBytesSync(png!.buffer.asUint8List());
    });
    _shots['$chapter-$name'] = {
      'width': kPhone.width,
      'height': kPhone.height,
      'scale': kDpr,
      'marks': [
        for (final t in targets)
          {
            'x': t.rect.left,
            'y': t.rect.top,
            'w': t.rect.width,
            'h': t.rect.height,
            'kind': t.mark.name,
          },
      ],
    };
  }

  /// Writes the marks for the annotator. Call at the end of the test.
  void finish() {
    final f = File('$_outDir/$chapter.$lang.json');
    f.writeAsStringSync(const JsonEncoder.withIndent(' ').convert(_shots));
    debugTakePlatePhoto = null;
    debugDisableShadows = true;
  }

  /// The control around [f] (a button's label or icon): what to outline.
  Finder control(Finder f) => find.ancestor(
    of: f,
    matching: find.byWidgetPredicate(
      (w) =>
          w is InkWell ||
          w is InkResponse ||
          w is FloatingActionButton ||
          w is NavigationDestination,
    ),
  );

  Future<void> tap(Finder f, {bool settleAfter = true}) async {
    await tester.ensureVisible(f.first);
    await tester.pumpAndSettle();
    await tester.tap(f.first);
    if (settleAfter) await settle();
  }

  Future<void> longPress(Finder f) async {
    await tester.longPress(f.first);
    await settle();
  }

  Future<void> enter(Finder f, String text) async {
    await tester.ensureVisible(f.first);
    await tester.enterText(f.first, text);
    await tester.pump();
  }

  /// Scrolls until [f] is on screen.
  Future<void> show(Finder f) async {
    await tester.ensureVisible(f.first);
    await tester.pumpAndSettle();
  }

  Future<void> back() async {
    await navigator.maybePop();
    await settle();
  }
}

/// Runs [body] once per language.
void chapter(String name, Future<void> Function(Manual m) body) {
  for (final lang in ['en', 'th']) {
    testWidgets('$name ($lang)', (tester) async {
      final m = Manual(tester, name, lang);
      await body(m);
      m.finish();
    });
  }
}

/// Text in the current language: `t('Save', 'บันทึก')`.
extension Lang on Manual {
  String t(String en, String th) => lang == 'th' ? th : en;
  Finder text(String en, String th) => find.text(t(en, th));
  Finder tip(String en, String th) => find.byTooltip(t(en, th));
}
