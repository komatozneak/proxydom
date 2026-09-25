import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teremok_connect/features/settings/data/auto_reconnect_prefs.dart';
import 'package:teremok_connect/features/settings/presentation/settings_screen.dart';
import 'package:teremok_connect/l10n/app_localizations.dart';

Widget _settingsApp() {
  return ProviderScope(
    child: const MaterialApp(
      locale: Locale('ru'),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      home: SettingsScreen(),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('iOS free client leaves reconnect to the packet tunnel', () async {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    expect(await AutoReconnectPrefs.isEnabled(), isFalse);
  });

  test('iOS free client ignores a stored on pref', () async {
    SharedPreferences.setMockInitialValues({'auto_reconnect_enabled': true});
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    expect(await AutoReconnectPrefs.isEnabled(), isFalse);
  });

  test('Android free client leaves reconnect to the native engine', () async {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    expect(await AutoReconnectPrefs.isEnabled(), isFalse);
  });

  test('configurator leaves reconnect to the native engine', () async {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    expect(await AutoReconnectPrefs.isEnabled(), isFalse);
  });

  testWidgets('iOS Settings hides the auto-reconnect switch', (tester) async {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(_settingsApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Авто-переподключение'), findsNothing);
    expect(find.text('Подключение'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Android Settings hides the account auto-reconnect switch',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(_settingsApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Авто-переподключение'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
}
