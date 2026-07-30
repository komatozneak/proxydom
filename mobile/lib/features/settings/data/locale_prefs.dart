import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted app language (`en` / `ru`). Default when unset: keep [fallback].
class LocalePrefs {
  LocalePrefs._();

  static const _key = 'app_locale';

  static const supported = <String>['en', 'ru'];

  static Future<Locale?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || !supported.contains(raw)) return null;
    return Locale(raw);
  }

  static Future<void> write(Locale locale) async {
    final code = locale.languageCode;
    if (!supported.contains(code)) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, code);
  }
}
