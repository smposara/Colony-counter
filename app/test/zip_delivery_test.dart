// ZIP exports on phones: written to a temporary folder, then shared. Earlier
// exports are cleaned up without touching one still being written, shared
// or read by the receiving app; the same menu export cannot run twice at once.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:colony_counter/data/plate_store.dart';
import 'package:colony_counter/data/sample_info.dart';
import 'package:colony_counter/data/storage/storage.dart';
import 'package:colony_counter/data/zip_delivery/zip_delivery.dart';
import 'package:colony_counter/l10n/l10n.dart';
import 'package:colony_counter/ui/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

class _FakePath extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePath(this.path);

  final String path;

  @override
  Future<String?> getTemporaryPath() async => path;
}

/// Records whether each shared file was there, whole; [hold] keeps the share
/// sheet open until it completes.
class _FakeShare extends SharePlatform with MockPlatformInterfaceMixin {
  final seen = <String, bool>{};
  Completer<void>? hold;

  @override
  Future<ShareResult> share(ShareParams params) async {
    for (final f in params.files!) {
      seen[f.path] = File(f.path).existsSync() && File(f.path).lengthSync() > 0;
    }
    await hold?.future;
    return const ShareResult('ok', ShareResultStatus.success);
  }
}

void main() {
  late Directory tmp;
  // One for all tests: SharePlus keeps the first platform it sees.
  final share = _FakeShare();
  SharePlatform.instance = share;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('cc_delivery');
    addTearDown(() => tmp.delete(recursive: true));
    PathProviderPlatform.instance = _FakePath(tmp.path);
    share
      ..seen.clear()
      ..hold = null;
  });

  test('a second export leaves the first one, still writing, alone', () async {
    final slow = StreamController<Uint8List>();
    final first = deliverZip(slow.stream, 'backup.zip', 's');
    slow.add(Uint8List(1000));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await deliverZip(Stream.value(Uint8List(10)), 'training.zip', 's');
    slow.add(Uint8List(1000));
    await slow.close();
    await first;
    expect(share.seen, hasLength(2));
    expect(share.seen.values, everyElement(isTrue));
  });

  test('exports an hour old are removed, recent ones kept', () async {
    final parent = Directory('${tmp.path}/colony-backup');
    final old = await Directory('${parent.path}/old').create(recursive: true);
    final recent = await Directory('${parent.path}/recent').create();
    final r = await Process.run('touch', ['-d', '2 hours ago', old.path]);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    await deliverZip(Stream.value(Uint8List(10)), 'backup.zip', 's');
    expect(old.existsSync(), isFalse);
    expect(recent.existsSync(), isTrue);
    expect(share.seen.keys.single, startsWith(parent.path));
  });

  testWidgets('the same export cannot start twice at once', (tester) async {
    final store = PlateStore(MemoryStorage());
    await tester.runAsync(() async {
      await store.load();
      await store.upsertSample(
        SampleInfo(sampleId: 'Lake-A', dilutions: const [4], replicates: 1),
      );
    });
    share.hold = Completer<void>();
    await tester.pumpWidget(MaterialApp(home: HomeScreen(store: store)));
    await tester.pumpAndSettle();
    Future<void> backUp() async {
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text(tr.homeBackUpAll));
      await tester.pump();
    }

    Future<void> until(bool Function() done) async {
      for (var i = 0; i < 100 && !done(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
    }

    await backUp();
    await until(() => share.seen.isNotEmpty);
    expect(share.seen, hasLength(1));
    // The share sheet is still open: a second backup is refused.
    await backUp();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(tr.homeExportRunning), findsOneWidget);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    expect(share.seen, hasLength(1));
    // Once it is done, the next one runs.
    share.hold!.complete();
    share.hold = null;
    await until(() => find.text(tr.homeExportRunning).evaluate().isEmpty);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await backUp();
    await until(() => share.seen.length == 2);
    expect(share.seen, hasLength(2));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
