import 'package:shared_preferences/shared_preferences.dart';

import 'split_tunnel_prefs.dart';

/// How traffic is routed while VPN is up.
enum VpnRouteMode {
  /// RU geosite (domain) → direct; rest → proxy (+ optional custom directs).
  /// geoip-ru intentionally OFF (see vpn_route_policy kGeoipRuEnabled).
  smart,

  /// Everything → proxy (except control-plane / VPS).
  full,

  /// Enabled sites → proxy; everything else → direct (allowlist).
  ///
  /// Empty selection falls back to full proxy so Android VpnService keeps a
  /// live default path (tray key + connectivity validation).
  sites,
}

/// Persist + draft bump for [VpnRouteMode] (reconnect-to-apply).
class VpnRouteModePrefs {
  VpnRouteModePrefs._();

  static const _key = 'vpn_route_mode_v1';

  /// Default [VpnRouteMode.smart] — matches historical bundled-RU ON.
  static Future<VpnRouteMode> getMode() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    return switch (raw) {
      'full' => VpnRouteMode.full,
      'sites' => VpnRouteMode.sites,
      'smart' || null => VpnRouteMode.smart,
      _ => VpnRouteMode.smart,
    };
  }

  static Future<void> setMode(VpnRouteMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    final value = switch (mode) {
      VpnRouteMode.smart => 'smart',
      VpnRouteMode.full => 'full',
      VpnRouteMode.sites => 'sites',
    };
    await prefs.setString(_key, value);
    await SplitTunnelPrefs.bumpDraftRev();
  }
}
