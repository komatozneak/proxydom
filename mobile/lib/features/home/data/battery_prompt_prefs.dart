import 'package:shared_preferences/shared_preferences.dart';

/// One-shot prompt so Android is less likely to freeze the tunnel.
class BatteryPromptPrefs {
  BatteryPromptPrefs._();

  static const _key = 'battery_prompt_dismissed_v1';

  static Future<bool> isDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) == true;
  }

  static Future<void> dismiss() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
  }
}
