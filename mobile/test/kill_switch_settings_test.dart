import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teremok_connect/features/settings/data/auto_reconnect_prefs.dart';
import 'package:teremok_connect/features/vpn/data/vpn_controller.dart';

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

    test('queryLockdownState maps snapshot map lockdown+alwaysOn', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        return <String, Object?>{
          'lockdown': false,
          'alwaysOn': true,
        };
      });
      expect(
        await VpnController.instance.queryLockdownState(),
        VpnLockdownState.alwaysOnOnly,
      );
    });

    test('queryLockdownState maps null lockdown → unavailable', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        return <String, Object?>{
          'lockdown': null,
          'alwaysOn': null,
          'secureLockdown': null,
          'runtimeLockdown': null,
        };
      });
      expect(
        await VpnController.instance.queryLockdownState(),
        VpnLockdownState.unavailable,
      );
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

  test('AutoReconnectPrefs remains independent storage', () async {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    expect(await AutoReconnectPrefs.isEnabled(), isFalse);
    await AutoReconnectPrefs.setEnabled(false);
    expect(await AutoReconnectPrefs.isEnabled(), isFalse);
    await AutoReconnectPrefs.setEnabled(true);
    expect(await AutoReconnectPrefs.isEnabled(), isFalse);
  });

  test('Settings does not ship a kill-switch tile (ADR 020)', () {
    final settings = File(
      'lib/features/settings/presentation/settings_screen.dart',
    ).readAsStringSync();
    expect(settings.contains('KillSwitchSettingsTile'), isFalse);
    expect(
      File('lib/features/settings/presentation/kill_switch_settings_tile.dart')
          .existsSync(),
      isFalse,
    );
  });
}
