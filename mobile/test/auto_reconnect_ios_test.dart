import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teremok_connect/features/settings/application/subscription_status_provider.dart';
import 'package:teremok_connect/features/settings/data/auto_reconnect_prefs.dart';
import 'package:teremok_connect/features/settings/data/subscription_status.dart';
import 'package:teremok_connect/features/settings/presentation/settings_screen.dart';
import 'package:teremok_connect/l10n/app_localizations.dart';

class _FixedSubNotifier extends SubscriptionStatusNotifier {
  _FixedSubNotifier(this._status);

  final SubscriptionStatus _status;

  @override
  Future<SubscriptionStatus> build() async => _status;
}

Widget _settingsApp() {
  return ProviderScope(
    overrides: [
      subscriptionStatusProvider.overrideWith(
        () => _FixedSubNotifier(SubscriptionStatus.empty),
      ),
    ],
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

  test('iOS auto-reconnect is always on without a pref', () async {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    expect(await AutoReconnectPrefs.isEnabled(), isTrue);
  });

  test('iOS auto-reconnect ignores a stored off pref', () async {
    SharedPreferences.setMockInitialValues({'auto_reconnect_enabled': false});
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    expect(await AutoReconnectPrefs.isEnabled(), isTrue);
  });

  test('Android auto-reconnect stays default off', () async {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    expect(await AutoReconnectPrefs.isEnabled(), isFalse);
    await AutoReconnectPrefs.setEnabled(true);
    expect(await AutoReconnectPrefs.isEnabled(), isTrue);
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

  testWidgets('Android Settings keeps the auto-reconnect switch', (tester) async {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(_settingsApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Авто-переподключение'), findsOneWidget);
    expect(find.byType(Switch), findsWidgets);
    debugDefaultTargetPlatformOverride = null;
  });
}
