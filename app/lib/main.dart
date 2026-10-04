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
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => MaterialApp(
        onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
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

/// Brand colours, shared with the Cells Calculator app and the app icon.
const kBrandBlue = Color(0xFF1565C0);
const kBrandOrange = Color(0xFFFF9800);

/// Blue as the main colour and orange as the accent. Light mode uses the
/// brand blue itself (white text on it: 5.7:1); dark mode uses the lighter
/// tones Material derives from it. Orange is a fill with dark text on it
/// (white on #FF9800 would be too faint).
///
/// Text uses the bundled Roboto, with IBM Plex Sans Thai for Thai and a
/// small symbol font for superscripts (10⁻⁵) that Roboto lacks, so text never
/// depends on downloaded or system fonts.
ThemeData _theme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final orange = ColorScheme.fromSeed(
    seedColor: kBrandOrange,
    brightness: brightness,
  );
  var scheme = ColorScheme.fromSeed(
    seedColor: kBrandBlue,
    brightness: brightness,
  );
  scheme = scheme.copyWith(
    primary: dark ? scheme.primary : kBrandBlue,
    onPrimary: dark ? scheme.onPrimary : Colors.white,
    tertiary: orange.primary,
    onTertiary: orange.onPrimary,
    tertiaryContainer: orange.primaryContainer,
    onTertiaryContainer: orange.onPrimaryContainer,
  );
  const onOrange = Color(0xFF2B1700);
  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: 'Roboto',
    appBarTheme: AppBarTheme(
      // A blue bar in light mode, like Cells Calculator; the usual dark
      // surface in dark mode.
      backgroundColor: dark ? null : kBrandBlue,
      foregroundColor: dark ? null : Colors.white,
      systemOverlayStyle: SystemUiOverlayStyle.light,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: kBrandOrange,
      foregroundColor: onOrange,
    ),
  );
  const fallback = ['IBMPlexSansThai', 'ColonySymbols'];
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamilyFallback: fallback),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamilyFallback: fallback),
  );
}
