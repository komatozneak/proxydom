import 'package:shared_preferences/shared_preferences.dart';

/// One-shot recovery code archive (shown once after first register).
class RecoveryCodeStorage {
  RecoveryCodeStorage._();
  static final RecoveryCodeStorage instance = RecoveryCodeStorage._();

  static const _pendingKey = 'auth.recovery_code.pending';
  static const _archivedKey = 'auth.recovery_code.archived';
  static const _shownKey = 'auth.recovery_code.shown';

  Future<void> savePending(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingKey, code);
    await prefs.setString(_archivedKey, code);
    await prefs.setBool(_shownKey, false);
  }

  Future<String?> takePending() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_pendingKey);
    if (code == null || code.isEmpty) return null;
    await prefs.remove(_pendingKey);
    return code;
  }

  Future<String?> readArchived() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_archivedKey);
  }

  Future<bool> wasShown() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_shownKey) ?? false;
  }

  Future<void> markShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_shownKey, true);
    await prefs.remove(_pendingKey);
  }
}
