import 'package:shared_preferences/shared_preferences.dart';

/// Persisted VPN session facts for diagnostics and Flutter restore
/// (RU rule-sets, winner label/protocol — not a new mint).
class VpnSessionMeta {
  VpnSessionMeta._();

  static const _ruRulesLoadedKey = 'vpn_ru_rules_loaded';
  static const _ruRulesTagsKey = 'vpn_ru_rules_tags';
  static const _expectedEgressHostKey = 'vpn_expected_egress_host';
  static const _winnerNodeIdKey = 'vpn_winner_node_id';
  static const _displayLabelKey = 'vpn_session_display_label';
  static const _protocolKey = 'vpn_session_protocol';

  static Future<void> saveConnectMeta({
    bool? ruRulesLoaded,
    List<String>? ruRuleTags,
    String? expectedEgressHost,
    bool updateExpectedHost = true,
    String? winnerNodeId,
    String? displayLabel,
    String? protocol,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (ruRulesLoaded != null) {
      await prefs.setBool(_ruRulesLoadedKey, ruRulesLoaded);
    }
    if (ruRuleTags != null) {
      await prefs.setString(_ruRulesTagsKey, ruRuleTags.join(','));
    }
    if (updateExpectedHost) {
      if (expectedEgressHost != null && expectedEgressHost.isNotEmpty) {
        await prefs.setString(_expectedEgressHostKey, expectedEgressHost);
      } else {
        await prefs.remove(_expectedEgressHostKey);
      }
    }
    if (winnerNodeId != null) {
      if (winnerNodeId.isNotEmpty) {
        await prefs.setString(_winnerNodeIdKey, winnerNodeId);
      } else {
        await prefs.remove(_winnerNodeIdKey);
      }
    }
    if (displayLabel != null) {
      if (displayLabel.isNotEmpty) {
        await prefs.setString(_displayLabelKey, displayLabel);
      } else {
        await prefs.remove(_displayLabelKey);
      }
    }
    if (protocol != null) {
      if (protocol.isNotEmpty) {
        await prefs.setString(_protocolKey, protocol);
      } else {
        await prefs.remove(_protocolKey);
      }
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_ruRulesLoadedKey);
    await prefs.remove(_ruRulesTagsKey);
    await prefs.remove(_expectedEgressHostKey);
    await prefs.remove(_winnerNodeIdKey);
    await prefs.remove(_displayLabelKey);
    await prefs.remove(_protocolKey);
  }

  static Future<
      ({
        bool ruRulesLoaded,
        List<String> ruRuleTags,
        String? expectedEgressHost,
        String? winnerNodeId,
        String? displayLabel,
        String? protocol,
      })> load() async {
    final prefs = await SharedPreferences.getInstance();
    final tagsRaw = prefs.getString(_ruRulesTagsKey) ?? '';
    final tags = tagsRaw.isEmpty
        ? <String>[]
        : tagsRaw.split(',').where((t) => t.isNotEmpty).toList();
    return (
      ruRulesLoaded: prefs.getBool(_ruRulesLoadedKey) ?? false,
      ruRuleTags: tags,
      expectedEgressHost: prefs.getString(_expectedEgressHostKey),
      winnerNodeId: prefs.getString(_winnerNodeIdKey),
      displayLabel: prefs.getString(_displayLabelKey),
      protocol: prefs.getString(_protocolKey),
    );
  }
}
