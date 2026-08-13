import 'package:shared_preferences/shared_preferences.dart';

/// One-time Play policy disclosure before first VPN connect (VpnService).
class VpnDisclosurePrefs {
  VpnDisclosurePrefs._();

  static const _key = 'vpn_disclosure_accepted_v1';

  static Future<bool> isAccepted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  static Future<void> markAccepted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
  }
}
