import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_locale.dart';
import '../data/locale_prefs.dart';

/// App-wide locale preference (persisted). Default: [AppLocale.current] (ru).
final localeProvider =
    AsyncNotifierProvider<LocaleNotifier, Locale>(LocaleNotifier.new);

class LocaleNotifier extends AsyncNotifier<Locale> {
  @override
  Future<Locale> build() async {
    final stored = await LocalePrefs.read();
    final locale = stored ?? AppLocale.current;
    AppLocale.set(locale);
    return locale;
  }

  Future<void> setLocale(Locale locale) async {
    final code = locale.languageCode;
    if (!LocalePrefs.supported.contains(code)) return;
    final next = Locale(code);
    AppLocale.set(next);
    state = AsyncData(next);
    await LocalePrefs.write(next);
  }
}
