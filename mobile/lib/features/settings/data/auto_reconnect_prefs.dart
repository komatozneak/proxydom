import 'package:shared_preferences/shared_preferences.dart';

/// In-app auto-reconnect after unexpected VPN drop (revoked / error).
///
/// Distinct from Android system Always-on VPN / lockdown (Kill switch).
class AutoReconnectPrefs {
  AutoReconnectPrefs._();

  static const _key = 'auto_reconnect_enabled';

  /// Default OFF — opt-in for new installs.
  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }
}
