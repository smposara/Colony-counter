// Helpers shared by the samples, labels and multi chapters of the manual.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:colony_counter/core/classical.dart';
import 'package:colony_counter/core/labels.dart';
import 'package:colony_counter/core/plate.dart';
import 'package:colony_counter/data/plate_record.dart';
import 'package:colony_counter/data/plate_store.dart';
import 'package:colony_counter/data/sample_info.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'harness.dart';

/// A sample plan like one set up on the New sample screen.
SampleInfo planFor(
  String id, {
  String experiment = 'Chlorine test',
  String condition = '1 % NaOCl',
  double? timeH = 2,
  List<int> dilutions = const [4, 5],
  int replicates = 2,
}) => SampleInfo(
  sampleId: id,
  experiment: experiment,
  condition: condition,
  timeH: timeH,
  dilutions: dilutions,
  replicates: replicates,
  strain: 'E. coli ATCC 25922',
  medium: 'PCA',
  incubationH: 48,
  incubationTempC: 35,
  operator: 'Somchai',
);

/// Saves a counted plate with [count] colonies on [fixtureName]'s photo.
/// Run inside `tester.runAsync`.
Future<void> seedPlate(
  PlateStore store,
  String sampleId,
  int dilutionExp,
  int replicate,
  int count, {
  String fixtureName = 'medium.jpg',
}) async {
  final rnd = math.Random(dilutionExp * 10 + replicate);
  final colonies = [
    for (var i = 0; i < count; i++)
      () {
        final a = rnd.nextDouble() * 2 * math.pi;
        final r = 380 * math.sqrt(rnd.nextDouble());
        return Colony(500 + r * math.cos(a), 500 + r * math.sin(a), 8);
      }(),
  ];
  await store.saveCapture(
    PlateRecord(
      id: 'seed-$sampleId-$dilutionExp-$replicate',
      createdAt: DateTime(2026, 10, 14, 9, dilutionExp * 10 + replicate),
      imagePath: '',
      imageWidth: 1000,
      imageHeight: 1000,
      plate: const Plate(500, 500, 420),
      colonies: colonies,
      autoCount: count,
      sampleId: sampleId,
      dilutionExp: dilutionExp,
      replicate: replicate,
      guided: true,
    ),
    fixture(fixtureName),
  );
}

/// An invisible box at [rect] (screen coordinates) to put a callout on a
/// spot that is not a button of its own, e.g. a plate in a photo or a text
/// field. It holds an [InkWell], so the harness outlines exactly [rect].
class Spot {
  Spot(this.m, Rect rect) {
    entry = OverlayEntry(
      builder: (_) => Positioned.fromRect(
        rect: rect,
        child: IgnorePointer(
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: () {},
              child: SizedBox.expand(key: key),
            ),
          ),
        ),
      ),
    );
    m.navigator.overlay!.insert(entry);
  }

  final Manual m;
  final key = UniqueKey();
  late final OverlayEntry entry;

  Finder get finder => find.byKey(key);

  void remove() => entry.remove();
}

/// [Manual.shot] that also takes marks on things without an [InkWell]
/// (text fields, a spot on a photo: [at]), which the harness cannot
/// outline as a control.
Future<void> snap(Manual m, String name, List<(Object, Mark)> marks) async {
  final made = <Spot>[];
  final out = <(Finder, Mark)>[];
  for (final (what, kind) in marks) {
    if (what is Rect) {
      made.add(Spot(m, what));
      out.add((made.last.finder, kind));
      continue;
    }
    final f = what as Finder;
    final bare =
        kind != Mark.look &&
        kind != Mark.drag &&
        f.evaluate().isNotEmpty &&
        find
            .ancestor(
              of: f.first,
              matching: find.byWidgetPredicate(
                (w) =>
                    w is InkWell ||
                    w is InkResponse ||
                    w is FloatingActionButton ||
                    w is NavigationDestination,
              ),
            )
            .evaluate()
            .isEmpty;
    if (bare) {
      made.add(Spot(m, m.tester.getRect(f.first)));
      out.add((made.last.finder, kind));
    } else {
      out.add((f, kind));
    }
  }
  await m.tester.pump();
  await m.shot(name, out);
  for (final s in made) {
    s.remove();
  }
  await m.tester.pump();
}

/// Catches what the app shares (the share sheet is the phone's own) and
/// returns the shared files' paths as they arrive.
List<String> catchShares(WidgetTester tester, String tempDir) {
  final shared = <String>[];
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => tempDir,
  );
  messenger.setMockMethodCallHandler(
    const MethodChannel('dev.fluttercommunity.plus/share'),
    (call) async {
      final args = call.arguments as Map;
      shared.addAll([for (final p in args['paths'] as List) '$p']);
      return 'dev.fluttercommunity.plus/share/success';
    },
  );
  addTearDown(() {
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/share'),
      null,
    );
  });
  return shared;
}

/// Renders the top [heightMm] of the first page of [pdf] to PNG bytes
/// (needs `pdftoppm`); null when it cannot. Run inside `tester.runAsync`.
Future<Uint8List?> pdfPage(
  String pdf, {
  int dpi = 200,
  double heightMm = 297,
}) async {
  final out = '${File(pdf).parent.path}/page';
  final w = (210 / 25.4 * dpi).round(), h = (heightMm / 25.4 * dpi).round();
  try {
    final r = await Process.run('pdftoppm', [
      '-png',
      '-r',
      '$dpi',
      '-f',
      '1',
      '-l',
      '1',
      '-x',
      '0',
      '-y',
      '0',
      '-W',
      '$w',
      '-H',
      '$h',
      '-singlefile',
      pdf,
      out,
    ]);
    if (r.exitCode != 0) return null;
    return File('$out.png').readAsBytesSync();
  } on ProcessException {
    return null;
  }
}

/// A photo of a printed plate label (its QR code on white).
Uint8List labelPhoto(String sampleId, {int? dilutionExp, int? replicate}) =>
    img.encodePng(
      renderLabelQr(
        PlateLabel(sampleId, dilutionExp: dilutionExp, replicate: replicate),
      ),
    );

/// Shows [png] full width on a plain page titled [title]: what the phone's
/// own viewer would show for a file the app shares.
Future<void> showFile(Manual m, String title, Uint8List png) async {
  unawaited(
    m.navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(title)),
          backgroundColor: Colors.grey.shade300,
          body: ListView(
            padding: const EdgeInsets.all(8),
            children: [Image.memory(png, fit: BoxFit.fitWidth)],
          ),
        ),
      ),
    ),
  );
  await m.settle();
}

/// The screen's main list.
Finder mainList() => find
    .descendant(
      of: find.byType(ListView).last,
      matching: find.byType(Scrollable),
    )
    .first;

/// Scrolls the screen's list back to the top.
Future<void> toTop(Manual m) async {
  await m.tester.drag(mainList(), const Offset(0, 3000));
  await m.settle();
}

/// Scrolls the screen's list until [f] is on screen, [align] of the way
/// down the screen (0 = top).
Future<void> reveal(Manual m, Finder f, {double align = 0.1}) async {
  await toTop(m);
  await m.tester.scrollUntilVisible(f, 150, scrollable: mainList());
  unawaited(
    Scrollable.ensureVisible(m.tester.element(f.first), alignment: align),
  );
  await m.settle();
}
