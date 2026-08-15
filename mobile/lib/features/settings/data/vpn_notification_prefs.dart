import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One switch: visible shade card with «Отключить». Default ON.
class VpnNotificationPrefs {
  VpnNotificationPrefs._();

  static const _visibleKey = 'shade_notification_visible';
  static const _channel = MethodChannel('teremok/vpn');

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<bool> isEnabled() async {
    if (!isSupported) return false;
    final prefs = await SharedPreferences.getInstance();
    final local = prefs.getBool(_visibleKey) ?? true;
    try {
      final native =
          await _channel.invokeMethod<bool>('isShadeNotificationEnabled');
      return native ?? local;
    } on MissingPluginException {
      return local;
    } on PlatformException {
      return local;
    }
  }

  static Future<void> setEnabled(bool enabled) async {
    if (!isSupported) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_visibleKey, enabled);
    try {
      await _channel.invokeMethod<dynamic>(
        'setShadeNotificationEnabled',
        {'enabled': enabled},
      );
    } on MissingPluginException {
      // ignore
    } on PlatformException catch (e) {
      debugPrint('[VpnNotificationPrefs] setEnabled failed: $e');
    }
  }
}
