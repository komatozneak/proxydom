import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/features/settings/data/locale_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a fresh install on a phone the app does not speak opens in English',
      () async {
    final locale = await LocalePrefs.startup(
      device: const [Locale('pt', 'BR')],
      seenWelcome: false,
    );
    expect(locale, const Locale('en'));
  });

  test('a fresh install on a Russian phone opens in Russian', () async {
    final locale = await LocalePrefs.startup(
      device: const [Locale('ru', 'RU')],
      seenWelcome: false,
    );
    expect(locale, const Locale('ru'));
  });

  test('the first device language the app speaks wins, not the first listed',
      () async {
    final locale = await LocalePrefs.startup(
      device: const [Locale('de'), Locale('ru'), Locale('en')],
      seenWelcome: false,
    );
    expect(locale, const Locale('ru'));
  });

  test('a fresh install keeps following the device after the welcome',
      () async {
    await LocalePrefs.startup(
      device: const [Locale('en', 'US')],
      seenWelcome: false,
    );
    // Next launch: the welcome is behind it and the phone is now Russian.
    final next = await LocalePrefs.startup(
      device: const [Locale('ru')],
      seenWelcome: true,
    );
    expect(next, const Locale('ru'));
    expect(await LocalePrefs.read(), isNull);
  });

  test('an install from before keeps Russian on an English phone', () async {
    final locale = await LocalePrefs.startup(
      device: const [Locale('en', 'US')],
      seenWelcome: true,
    );
    expect(locale, const Locale('ru'));
    // Pinned, so a later launch does not reconsider it.
    expect(await LocalePrefs.read(), const Locale('ru'));
  });

  test('a language chosen in Settings beats the device', () async {
    await LocalePrefs.write(const Locale('en'));
    final locale = await LocalePrefs.startup(
      device: const [Locale('ru')],
      seenWelcome: true,
    );
    expect(locale, const Locale('en'));
  });
}
