import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Detailed VPN shade notification (region · VLESS, speeds, disconnect).
class VpnNotificationPrefs {
  VpnNotificationPrefs._();

  static const _prefsKey = 'vpn_notification_detailed';
  static const _channel = MethodChannel('teremok/vpn');

  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  static Future<bool> isEnabled() async {
    if (!isSupported) return false;
    final prefs = await SharedPreferences.getInstance();
    final local = prefs.getBool(_prefsKey) ?? true;
    try {
      final native =
          await _channel.invokeMethod<bool>('isVpnNotificationDetailedEnabled');
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
    await prefs.setBool(_prefsKey, enabled);
    try {
      await _channel.invokeMethod<dynamic>(
        'setVpnNotificationDetailedEnabled',
        {'enabled': enabled},
      );
    } on MissingPluginException {
      // ignore
    } on PlatformException catch (e) {
      debugPrint('[VpnNotificationPrefs] setEnabled failed: $e');
    }
  }
}
