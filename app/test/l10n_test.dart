import 'dart:convert';
import 'dart:io';

import 'package:colony_counter/data/plate_store.dart';
import 'package:colony_counter/data/storage/storage.dart';
import 'package:colony_counter/l10n/l10n.dart';
import 'package:colony_counter/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _arb(String name) =>
    jsonDecode(File('lib/l10n/$name').readAsStringSync())
        as Map<String, dynamic>;

Set<String> _placeholders(String s) => {
  for (final m in RegExp(r'\{(\w+)[},]').allMatches(s)) m.group(1)!,
};

final _thaiChar = RegExp('[฀-๿]');

void main() {
  test('ARB files are up to date with lib/l10n/parts', () {
    final en = _arb('app_en.arb'), th = _arb('app_th.arb');
    final parts = <String, dynamic>{
      for (final f in Directory('lib/l10n/parts').listSync().whereType<File>())
        ...jsonDecode(f.readAsStringSync()) as Map<String, dynamic>,
    };
    for (final e in parts.entries) {
      final v = e.value as Map<String, dynamic>;
      expect(
        en[e.key],
        v['en'],
        reason: 'run python tool/merge_strings.py (${e.key})',
      );
      expect(
        th[e.key],
        v['th'],
        reason: 'run python tool/merge_strings.py (${e.key})',
      );
    }
    expect(en.keys.where((k) => !k.startsWith('@')).length, parts.length);
  });

  test('every string has a Thai translation with the same placeholders', () {
    final en = _arb('app_en.arb'), th = _arb('app_th.arb');
    for (final key in en.keys.where((k) => !k.startsWith('@'))) {
      final t = th[key] as String?;
      expect(t, isNotNull, reason: key);
      expect(t!.trim(), isNotEmpty, reason: key);
      // Thai may drop the plural selector but must use only known placeholders.
      expect(
        _placeholders(en[key] as String).containsAll(_placeholders(t)),
        isTrue,
        reason: key,
      );
    }
    // Most strings are actually in Thai (some are names or numbers only).
    final thai = th.entries
        .where(
          (e) => !e.key.startsWith('@') && _thaiChar.hasMatch('${e.value}'),
        )
        .length;
    final keys = en.keys.where((k) => !k.startsWith('@')).length;
    expect(thai, greaterThan(keys * 0.8));
  });

  Future<PlateStore> store(
    WidgetTester tester, {
    String language = 'system',
    String theme = 'system',
  }) async {
    final s = PlateStore(MemoryStorage());
    await tester.runAsync(s.load);
    s.language = language;
    s.theme = theme;
    return s;
  }

  testWidgets('the app runs in Thai when chosen', (tester) async {
    final s = await store(tester, language: 'th');
    await tester.pumpWidget(ColonyCounterApp(store: s));
    await tester.pump();
    expect(tr.localeName, 'th');
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .toList();
    expect(texts.where(_thaiChar.hasMatch), isNotEmpty);
    // Back to English for the other tests.
    s.language = 'en';
    await tester.pumpWidget(ColonyCounterApp(store: s));
    await tester.pump();
    expect(tr.localeName, 'en');
    expect(find.text('No plates yet'), findsOneWidget);
  });

  testWidgets('dark theme when chosen', (tester) async {
    final s = await store(tester, theme: 'dark', language: 'en');
    await tester.pumpWidget(ColonyCounterApp(store: s));
    await tester.pump();
    final context = tester.element(find.text('No plates yet'));
    expect(Theme.of(context).brightness, Brightness.dark);
  });
}
