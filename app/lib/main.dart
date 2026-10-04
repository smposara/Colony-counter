import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/plate_store.dart';
import 'l10n/l10n.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  _registerFontLicences();
  final store = await PlateStore.open();
  runApp(ColonyCounterApp(store: store));
}

/// The bundled fonts' licences, listed under About → Open-source licences
/// next to those of the libraries.
void _registerFontLicences() {
  LicenseRegistry.addLicense(() async* {
    for (final (name, file) in const [
      ('Roboto (font)', 'LICENSE-Roboto.txt'),
      ('IBM Plex Sans Thai (font)', 'LICENSE-IBMPlexSansThai.txt'),
      ('DejaVu Sans, as ColonySymbols (font)', 'LICENSE-ColonySymbols.txt'),
    ]) {
      yield LicenseEntryWithLineBreaks([
        name,
      ], await rootBundle.loadString('assets/fonts/$file'));
    }
  });
}

class ColonyCounterApp extends StatelessWidget {
  const ColonyCounterApp({super.key, required this.store});

  final PlateStore store;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF2E7D6B);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => MaterialApp(
        onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
        theme: _theme(seed, Brightness.light),
        darkTheme: _theme(seed, Brightness.dark),
        themeMode: switch (store.theme) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          _ => ThemeMode.system,
        },
        locale: switch (store.language) {
          'en' => const Locale('en'),
          'th' => const Locale('th'),
          _ => null,
        },
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) {
          final l = AppLocalizations.of(context);
          setCurrentStrings(l);
          // A new language rebuilds every screen, so no text stays in the
          // old one (the app returns to the home screen).
          return KeyedSubtree(key: ValueKey(l?.localeName), child: child!);
        },
        home: HomeScreen(store: store),
      ),
    );
  }
}

/// Bundled Roboto, with IBM Plex Sans Thai for Thai and a small symbol font
/// for superscripts (10⁻⁵) that Roboto lacks, so text never depends on
/// downloaded or system fonts.
ThemeData _theme(Color seed, Brightness brightness) {
  final base = ThemeData(
    colorSchemeSeed: seed,
    brightness: brightness,
    useMaterial3: true,
    fontFamily: 'Roboto',
  );
  const fallback = ['IBMPlexSansThai', 'ColonySymbols'];
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamilyFallback: fallback),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamilyFallback: fallback),
  );
}
