import 'package:flutter/material.dart';

/// In-memory locale mirror for tests / early boot before prefs load.
/// Preference SoT: localeProvider + SharedPreferences.
///
/// main() sets it from LocalePrefs.startup before the first frame; Russian is
/// only what a test or a code path outside the app sees without that.
class AppLocale {
  AppLocale._();

  static Locale _current = const Locale('ru');

  static Locale get current => _current;

  static void set(Locale locale) {
    _current = locale;
  }

  static const supportedLocales = [
    Locale('en'),
    Locale('ru'),
  ];
}
