import 'package:shared_preferences/shared_preferences.dart';

/// Onboarding completion keyed by user id + onboarding version.
///
/// Survives logout: keys are not cleared with tokens.
class OnboardingPrefs {
  OnboardingPrefs._();

  /// Bump when informational cards change enough to re-show.
  static const int currentVersion = 1;

  static const _welcomeSeenKey = 'beta_welcome_seen_v1';

  static String _completedKey(String userId, int version) =>
      'onboarding_done_${userId}_v$version';

  static Future<bool> isCompleted({
    required String userId,
    int version = currentVersion,
  }) async {
    if (userId.isEmpty) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_completedKey(userId, version)) == true;
  }

  static Future<void> markCompleted({
    required String userId,
    int version = currentVersion,
  }) async {
    if (userId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_completedKey(userId, version), true);
  }

  static Future<bool> isWelcomeSeen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_welcomeSeenKey) == true;
  }

  static Future<void> markWelcomeSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_welcomeSeenKey, true);
  }
}
