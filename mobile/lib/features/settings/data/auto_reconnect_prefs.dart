import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/ios_store_gates.dart';

/// In-app auto-reconnect after unexpected VPN drop (revoked / error).
///
/// Distinct from Android system Always-on VPN / lockdown (Kill switch).
class AutoReconnectPrefs {
  AutoReconnectPrefs._();

  static const _key = 'auto_reconnect_enabled';

  /// Account client: default ON. Imported-profile clients delegate recovery to
  /// their native VPN session engine.
  static Future<bool> isEnabled() async {
    if (windowsDesktop) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_key) ?? false;
    }
    // Imported-profile clients let the native session engine own recovery.
    // A second Flutter reconnect races native dead-tunnel restore.
    if (freeKeyClient) return false;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      return true;
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? true;
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }
}
