import 'package:shared_preferences/shared_preferences.dart';

/// In-app auto-reconnect after unexpected VPN drop (revoked / error).
///
/// Distinct from Android system Always-on VPN / lockdown (Kill switch).
class AutoReconnectPrefs {
  AutoReconnectPrefs._();

  static const _key = 'auto_reconnect_enabled';

  /// Default ON — friends expect tunnel to come back after a drop.
  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? true;
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }
}
