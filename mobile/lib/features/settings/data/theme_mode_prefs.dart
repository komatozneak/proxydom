import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted [ThemeMode] (system / light / dark).
class ThemeModePrefs {
  ThemeModePrefs._();

  static const _key = 'theme_mode';

  static Future<ThemeMode> read() async {
    final prefs = await SharedPreferences.getInstance();
    return _fromStorage(prefs.getString(_key));
  }

  static Future<void> write(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, _toStorage(mode));
  }

  static String _toStorage(ThemeMode mode) => switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };

  static ThemeMode _fromStorage(String? raw) => switch (raw) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
}
