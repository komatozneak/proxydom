import 'package:shared_preferences/shared_preferences.dart';

import 'app_log_buffer.dart';
import 'tunnel_log_level.dart';

/// Persisted tunnel log level. Applied to [AppLogBuffer] on read and write.
class TunnelLogPrefs {
  TunnelLogPrefs._();

  static const _key = 'tunnel_log_level';

  static Future<TunnelLogLevel> read() async {
    final prefs = await SharedPreferences.getInstance();
    final level = TunnelLogLevel.fromStorage(prefs.getString(_key));
    AppLogBuffer.instance.minLevel = level;
    return level;
  }

  static Future<void> write(TunnelLogLevel level) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, level.name);
    AppLogBuffer.instance.minLevel = level;
  }
}
