import '../../../core/app_locale.dart';
import '../../../core/config.dart';
import 'node_display.dart';

/// User-facing brand name for VPN session / fallback labels (no Marzban id).
const kVpnBrandSessionName = 'Прокси Дом';

/// Scheme of the selected local line, as `dial_set.dart` names it.
///
/// These were declared beside the catalog `VpnNode` class, which went with the
/// account era. The schemes themselves are live: [sessionProtocolLabel] keys
/// off them, because a Hy2 or TrustTunnel line must not be labelled VLESS.
const kDialSchemeHysteria2 = 'hysteria2';
const kDialSchemeTrusttunnel = 'trusttunnel';

/// Normalize outbound type for native/UI (never `"unknown"`).
String normalizeOutboundType(String? type) {
  final t = (type ?? '').trim().toLowerCase();
  if (t.isEmpty || t == 'unknown') return 'vless';
  return t;
}

/// Protocol label for Home / notification (e.g. `VLESS`).
String friendlyProtocolLabel(String? type) =>
    normalizeOutboundType(type).toUpperCase();

/// Session protocol for logs / Home: Hy2 and TrustTunnel must not fall back to
/// VLESS.
String sessionProtocolLabel({String? selectedNodeProtocol}) {
  final selected = (selectedNodeProtocol ?? '').trim().toLowerCase();
  if (selected == kDialSchemeHysteria2) {
    return 'HYSTERIA2';
  }
  if (selected == kDialSchemeTrusttunnel) {
    return 'TRUSTTUNNEL';
  }
  if (selected.isNotEmpty) {
    return friendlyProtocolLabel(selected);
  }
  return friendlyProtocolLabel('vless');
}

String _uiLanguageCode() => AppLocale.current.languageCode;

String localizeVpnLabel(String raw) {
  final canonical = canonicalPlaceForProductLabel(raw);
  if (canonical != null) {
    return canonical.displayTitle(_uiLanguageCode());
  }
  final stripped = stripTierRole(raw);
  if (_uiLanguageCode() == 'en') {
    return englishTitleForProduct(stripped) ?? stripped;
  }
  return stripped;
}

/// Human label for the active hop; never Marzban `username`.
///
/// The explicit label the user's own line carries wins. There is nothing else to
/// fall back to now: the catalog host the old signature consulted came from the
/// backend config the local configurator never fetches, so the brand name is the
/// honest answer when no label is set.
String connectedServerName({String? displayLabel}) {
  final explicit = displayLabel?.trim();
  if (explicit != null && explicit.isNotEmpty) {
    return localizeVpnLabel(explicit);
  }
  return kVpnBrandSessionName;
}

/// Extra hosts for Android `excludeRoute`, so they stay off TUN. The selected
/// node is excluded separately as its own server. A hostname of the control
/// plane is not pinned to a baked-in address.
List<String> controlPlaneHostsOf() {
  final hosts = <String>{};
  try {
    final host = Uri.parse(AppConfig.baseUrl).host;
    if (RegExp(r'^(\d{1,3}\.){3}\d{1,3}$').hasMatch(host)) {
      hosts.add(host);
    }
  } catch (_) {
    // ignore malformed baseUrl in tests
  }
  return hosts.toList();
}

/// Host and port of a share line's `host:port` endpoint, or null when it has
/// none. The port is after the last colon, so a bare IPv6 host still splits.
({String host, int port})? shareServerOf(String? endpoint) {
  final text = (endpoint ?? '').trim();
  final colon = text.lastIndexOf(':');
  if (colon <= 0 || colon == text.length - 1) return null;
  final port = int.tryParse(text.substring(colon + 1));
  if (port == null || port < 1 || port > 65535) return null;
  var host = text.substring(0, colon);
  if (host.startsWith('[') && host.endsWith(']')) {
    host = host.substring(1, host.length - 1);
  }
  return host.isEmpty ? null : (host: host, port: port);
}
