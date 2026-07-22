import 'package:shared_preferences/shared_preferences.dart';

/// Persisted VPN session facts for diagnostics (RU rule-sets, egress host).
class VpnSessionMeta {
  VpnSessionMeta._();

  static const _ruRulesLoadedKey = 'vpn_ru_rules_loaded';
  static const _ruRulesTagsKey = 'vpn_ru_rules_tags';
  static const _expectedEgressHostKey = 'vpn_expected_egress_host';

  static Future<void> saveConnectMeta({
    required bool ruRulesLoaded,
    required List<String> ruRuleTags,
    String? expectedEgressHost,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_ruRulesLoadedKey, ruRulesLoaded);
    await prefs.setString(_ruRulesTagsKey, ruRuleTags.join(','));
    if (expectedEgressHost != null && expectedEgressHost.isNotEmpty) {
      await prefs.setString(_expectedEgressHostKey, expectedEgressHost);
    } else {
      await prefs.remove(_expectedEgressHostKey);
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_ruRulesLoadedKey);
    await prefs.remove(_ruRulesTagsKey);
    await prefs.remove(_expectedEgressHostKey);
  }

  static Future<({bool ruRulesLoaded, List<String> ruRuleTags, String? expectedEgressHost})>
      load() async {
    final prefs = await SharedPreferences.getInstance();
    final tagsRaw = prefs.getString(_ruRulesTagsKey) ?? '';
    final tags = tagsRaw.isEmpty
        ? <String>[]
        : tagsRaw.split(',').where((t) => t.isNotEmpty).toList();
    return (
      ruRulesLoaded: prefs.getBool(_ruRulesLoadedKey) ?? false,
      ruRuleTags: tags,
      expectedEgressHost: prefs.getString(_expectedEgressHostKey),
    );
  }
}
