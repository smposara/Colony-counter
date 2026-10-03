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
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: seed,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: HomeScreen(store: store),
    );
  }
}
