import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:teremok_connect/features/settings/data/access_status_copy.dart';
import 'package:teremok_connect/features/settings/data/locale_prefs.dart';
import 'package:teremok_connect/features/settings/data/subscription_status.dart';
import 'package:teremok_connect/features/settings/data/theme_mode_prefs.dart';

void main() {
  group('accessCopyKind', () {
    test('alpha entitlement maps to closed beta, not early-access fallback', () {
      const s = SubscriptionStatus(
        plan: 'alpha',
        status: 'active',
        isAlpha: true,
      );
      expect(accessCopyKind(s), AccessCopyKind.closedBeta);
    });

    test('empty status maps to free', () {
      expect(accessCopyKind(SubscriptionStatus.empty), AccessCopyKind.free);
    });

    test('paid active maps to paidOrTrial', () {
      const s = SubscriptionStatus(
        plan: '1m',
        status: 'active',
        isPro: true,
      );
      expect(accessCopyKind(s), AccessCopyKind.paidOrTrial);
    });

    test('trial maps to paidOrTrial', () {
      const s = SubscriptionStatus(
        plan: 'trial',
        status: 'active',
        isTrial: true,
      );
      expect(accessCopyKind(s), AccessCopyKind.paidOrTrial);
    });
  });

  group('ThemeModePrefs', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('defaults to system and persists choice', () async {
      expect(await ThemeModePrefs.read(), ThemeMode.system);
      await ThemeModePrefs.write(ThemeMode.dark);
      expect(await ThemeModePrefs.read(), ThemeMode.dark);
      await ThemeModePrefs.write(ThemeMode.light);
      expect(await ThemeModePrefs.read(), ThemeMode.light);
    });
  });

  group('LocalePrefs', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('returns null when unset and persists en/ru', () async {
      expect(await LocalePrefs.read(), isNull);
      await LocalePrefs.write(const Locale('en'));
      expect(await LocalePrefs.read(), const Locale('en'));
      await LocalePrefs.write(const Locale('ru'));
      expect(await LocalePrefs.read(), const Locale('ru'));
    });
  });
}
