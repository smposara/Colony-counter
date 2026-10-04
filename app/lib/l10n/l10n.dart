import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

export 'app_localizations.dart';

AppLocalizations _current = lookupAppLocalizations(const Locale('en'));

/// The app's strings in the current language.
///
/// Usable anywhere, including code without a BuildContext. The app rebuilds
/// every screen when the language changes (see `main.dart`), so text read
/// through [tr] never goes stale. Tests that pump a bare `MaterialApp` get
/// English.
AppLocalizations get tr => _current;

/// Sets the language used by [tr]; called by the app below its Localizations.
void setCurrentStrings(AppLocalizations? l) {
  if (l != null) _current = l;
}

/// Thai, when the current language is Thai (for small layout choices).
bool get isThai => _current.localeName == 'th';
