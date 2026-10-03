import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:proxydom/features/settings/data/vpn_notification_prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('proxydom/vpn');

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('shade notification defaults on and can be turned off', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'isShadeNotificationEnabled') {
        return true;
      }
      if (call.method == 'setShadeNotificationEnabled') {
        expect(call.arguments, {'enabled': false});
        return true;
      }
      return null;
    });

    expect(await VpnNotificationPrefs.isEnabled(), isTrue);
    await VpnNotificationPrefs.setEnabled(false);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('shade_notification_visible'), isFalse);
  });
}
