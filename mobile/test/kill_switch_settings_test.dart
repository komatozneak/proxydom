import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teremok_connect/features/settings/data/auto_reconnect_prefs.dart';
import 'package:teremok_connect/features/settings/presentation/kill_switch_settings_tile.dart';
import 'package:teremok_connect/features/vpn/data/vpn_controller.dart';
import 'package:teremok_connect/l10n/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VpnController lockdown / openVpnSettings', () {
    const channel = MethodChannel('teremok/vpn');
    final log = <MethodCall>[];

    setUp(() {
      log.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        log.add(call);
        switch (call.method) {
          case 'isLockdownEnabled':
            return true;
          case 'openVpnSettings':
            return true;
          default:
            return null;
        }
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('queryLockdownState maps true → enabled', () async {
      expect(
        await VpnController.instance.queryLockdownState(),
        VpnLockdownState.enabled,
      );
      expect(log.single.method, 'isLockdownEnabled');
    });

    test('queryLockdownState maps false → disabled', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        log.add(call);
        return false;
      });
      expect(
        await VpnController.instance.queryLockdownState(),
        VpnLockdownState.disabled,
      );
    });

    test('queryLockdownState maps PlatformException → unavailable', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'LOCKDOWN_QUERY_FAILED');
      });
      expect(
        await VpnController.instance.queryLockdownState(),
        VpnLockdownState.unavailable,
      );
    });

    test('openVpnSettings returns true on success', () async {
      expect(await VpnController.instance.openVpnSettings(), isTrue);
      expect(log.single.method, 'openVpnSettings');
    });

    test('openVpnSettings returns false on PlatformException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'VPN_SETTINGS_UNAVAILABLE');
      });
      expect(await VpnController.instance.openVpnSettings(), isFalse);
    });
  });

  group('KillSwitchSettingsTile', () {
    testWidgets('enabled → status + On badge, no Switch', (tester) async {
      var openCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: KillSwitchSettingsTile(
              queryLockdownState: () async => VpnLockdownState.enabled,
              openVpnSettings: () async {
                openCalls++;
                return true;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Enabled in Android settings'), findsOneWidget);
      expect(find.text('On'), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
      expect(find.byType(OutlinedButton), findsOneWidget);

      await tester.tap(find.text('Open VPN settings'));
      await tester.pumpAndSettle();
      expect(openCalls, 1);
    });

    testWidgets('disabled → Off badge, no Switch', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: KillSwitchSettingsTile(
              queryLockdownState: () async => VpnLockdownState.disabled,
              openVpnSettings: () async => true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Off — internet may work without VPN'),
        findsOneWidget,
      );
      expect(find.text('Off'), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
    });

    testWidgets('query failure → UNAVAILABLE, not OFF', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: KillSwitchSettingsTile(
              queryLockdownState: () async => VpnLockdownState.unavailable,
              openVpnSettings: () async => true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text("Couldn't check the Android setting"),
        findsOneWidget,
      );
      expect(
        find.text('Off — internet may work without VPN'),
        findsNothing,
      );
      expect(find.byType(Switch), findsNothing);
    });

    testWidgets('OutlinedButton opens settings; failure shows snackbar',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: KillSwitchSettingsTile(
              queryLockdownState: () async => VpnLockdownState.disabled,
              openVpnSettings: () async => false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(OutlinedButton));
      await tester.pumpAndSettle();

      expect(
        find.textContaining("Couldn't open VPN settings"),
        findsOneWidget,
      );
    });

    testWidgets('resume refreshes lockdown query', (tester) async {
      var queries = 0;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: KillSwitchSettingsTile(
              queryLockdownState: () async {
                queries++;
                return queries == 1
                    ? VpnLockdownState.disabled
                    : VpnLockdownState.enabled;
              },
              openVpnSettings: () async => true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(queries, 1);
      expect(find.text('Off'), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(queries, greaterThanOrEqualTo(2));
      expect(find.text('On'), findsOneWidget);
      expect(find.text('Enabled in Android settings'), findsOneWidget);

      // Flush the short post-resume retry timer.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(queries, greaterThanOrEqualTo(3));
      expect(find.text('On'), findsOneWidget);
    });

    testWidgets('return from VPN settings refreshes Off→On', (tester) async {
      var queries = 0;
      var lockdownOn = false;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: KillSwitchSettingsTile(
              queryLockdownState: () async {
                queries++;
                return lockdownOn
                    ? VpnLockdownState.enabled
                    : VpnLockdownState.disabled;
              },
              openVpnSettings: () async => true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Off'), findsOneWidget);

      await tester.tap(find.text('Open VPN settings'));
      await tester.pumpAndSettle();

      // User enables lockdown in system settings, then returns.
      lockdownOn = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      // Flush aggressive resume retries (350 + 900 + 1800).
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 1800));
      await tester.pumpAndSettle();

      expect(find.text('On'), findsOneWidget);
      expect(find.text('Enabled in Android settings'), findsOneWidget);
      expect(queries, greaterThan(2));
    });
  });

  test('AutoReconnectPrefs remains independent storage', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await AutoReconnectPrefs.isEnabled(), isTrue);
    await AutoReconnectPrefs.setEnabled(false);
    expect(await AutoReconnectPrefs.isEnabled(), isFalse);
  });
}
