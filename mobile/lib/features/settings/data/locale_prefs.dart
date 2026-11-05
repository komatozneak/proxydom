import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted app language (`en` / `ru`).
class LocalePrefs {
  LocalePrefs._();

  static const _key = 'app_locale';

  /// Set on an install that opened by the device's language. Without it, an
  /// install that has already been through the welcome screens predates that
  /// rule and has been reading Russian.
  static const _followsDeviceKey = 'app_locale_follows_device';

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

  /// The language this launch opens in.
  ///
  /// A choice made in Settings wins. Without one, the app follows the device:
  /// the first of its languages the app speaks, English when it speaks none.
  /// An install that saw the welcome screens before the app looked at the
  /// device keeps the Russian it has been reading, so an update does not
  /// switch a person's language under them.
  static Future<Locale> startup({
    required List<Locale> device,
    required bool seenWelcome,
  }) async {
    final stored = await read();
    if (stored != null) return stored;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_followsDeviceKey) != true) {
      if (seenWelcome) {
        const russian = Locale('ru');
        await write(russian);
        return russian;
      }
      await prefs.setBool(_followsDeviceKey, true);
    }
    return fromDevice(device);
  }

  /// The first of [device] the app speaks, else English: a phone set to
  /// Portuguese gets English, not Russian.
  static Locale fromDevice(List<Locale> device) {
    for (final locale in device) {
      if (supported.contains(locale.languageCode)) {
        return Locale(locale.languageCode);
      }
    }
    return const Locale('en');
  }
}
