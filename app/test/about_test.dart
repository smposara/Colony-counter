import 'dart:io';

import 'package:colony_counter/app_info.dart';
import 'package:colony_counter/ui/about_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('About version matches pubspec.yaml', () {
    final line = File('pubspec.yaml')
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('version:'));
    expect(line.trim(), 'version: $kAppVersion+$kAppBuild');
  });

  test('the repository has the licence the About page names', () {
    final licence = File('../LICENSE').readAsStringSync();
    expect(licence, startsWith('GNU AFFERO GENERAL PUBLIC LICENSE'));
    expect(kLicenseName, contains('AGPL-3.0'));
  });

  testWidgets('About shows version, developer and contacts', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: AboutScreen()));
    expect(find.text('Version $kAppVersion (build $kAppBuild)'), findsOneWidget);
    expect(find.text('Pongsak Sarapukdee'), findsOneWidget);
    expect(find.text('sarapukdee@gmail.com'), findsOneWidget);
    expect(find.text('https://cc.amphur.in.th'), findsOneWidget);
    expect(find.text('https://github.com/smposara/Colony-counter'), findsOneWidget);
    expect(find.text('Licence: GNU AGPL-3.0'), findsOneWidget);
  });

  testWidgets('open-source licences include the bundled fonts', (tester) async {
    LicenseRegistry.addLicense(() async* {
      yield const LicenseEntryWithLineBreaks(['IBM Plex Sans Thai (font)'], 'OFL');
    });
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: AboutScreen()));
    await tester.tap(find.text('Open-source licences'));
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(find.textContaining('IBM Plex Sans Thai'), findsWidgets);
  });
}
