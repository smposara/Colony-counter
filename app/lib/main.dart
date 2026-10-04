import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/plate_store.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final store = await PlateStore.open();
  runApp(ColonyCounterApp(store: store));
}

class ColonyCounterApp extends StatelessWidget {
  const ColonyCounterApp({super.key, required this.store});

  final PlateStore store;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF2E7D6B);
    return MaterialApp(
      title: 'Colony Counter',
      theme: _theme(seed, Brightness.light),
      darkTheme: _theme(seed, Brightness.dark),
      home: HomeScreen(store: store),
    );
  }
}

/// Bundled Roboto, with a small symbol font for superscripts (10⁻⁵) that
/// Roboto lacks, so text never depends on downloaded or system fonts.
ThemeData _theme(Color seed, Brightness brightness) {
  final base = ThemeData(
    colorSchemeSeed: seed,
    brightness: brightness,
    useMaterial3: true,
    fontFamily: 'Roboto',
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      fontFamilyFallback: const ['ColonySymbols'],
    ),
    primaryTextTheme: base.primaryTextTheme.apply(
      fontFamilyFallback: const ['ColonySymbols'],
    ),
  );
}
