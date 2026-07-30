import 'geo_ip_service.dart';
import 'vpn_node.dart';

/// Human-facing labels for Marzban nodes (ids like `node-185` are ops names).
class NodePlace {
  const NodePlace({
    required this.title,
    required this.subtitle,
    this.titleEn,
    this.subtitleEn,
    this.flag = '🌍',
  });

  final String title;
  final String subtitle;
  final String? titleEn;
  final String? subtitleEn;
  final String flag;

  String displayTitle(String languageCode) =>
      languageCode == 'en' && titleEn != null ? titleEn! : title;

  String displaySubtitle(String languageCode) =>
      languageCode == 'en' && subtitleEn != null ? subtitleEn! : subtitle;

  factory NodePlace.fromGeo(GeoIpResult geo) {
    return NodePlace(
      title: geo.displayCountry('ru'),
      titleEn: geo.country,
      subtitle: geo.displayCity('ru'),
      subtitleEn: geo.city.isNotEmpty ? geo.city : geo.region,
      flag: geo.flagEmoji,
    );
  }
}

/// Preference value: let backend / default pick the node.
const String kRegionAutoId = 'auto';

/// Product pool: host → country/city for the Locations list.
///
/// Edit when adding a VPS. Prefer this over GeoIP / Marzban ops names.
const Map<String, NodePlace> kKnownNodePlaces = {
  '204.11.2.216': NodePlace(
    title: 'Германия',
    subtitle: 'Франкфурт',
    titleEn: 'Germany',
    subtitleEn: 'Frankfurt',
    flag: '🇩🇪',
  ),
  '185.139.228.192': NodePlace(
    title: 'Нидерланды',
    subtitle: 'Амстердам',
    titleEn: 'Netherlands',
    subtitleEn: 'Amsterdam',
    flag: '🇳🇱',
  ),
  '217.60.11.56': NodePlace(
    title: 'Германия',
    subtitle: 'Франкфурт',
    titleEn: 'Germany',
    subtitleEn: 'Frankfurt',
    flag: '🇩🇪',
  ),
  '45.91.248.91': NodePlace(
    title: 'США',
    subtitle: 'Нью-Йорк',
    titleEn: 'USA',
    subtitleEn: 'New York',
    flag: '🇺🇸',
  ),
};

/// Strip `host:port` / whitespace so catalog keys match [kKnownNodePlaces].
String normalizeNodeHost(String host) {
  var h = host.trim();
  if (h.isEmpty) return h;
  // Bracketed IPv6 with port: [2001:db8::1]:443
  if (h.startsWith('[')) {
    final end = h.indexOf(']');
    if (end > 0) return h.substring(1, end);
  }
  // IPv4 or hostname with :port — keep bare IPv6 (multiple colons) intact.
  final colon = h.indexOf(':');
  if (colon > 0 && h.indexOf(':', colon + 1) < 0) {
    h = h.substring(0, colon);
  }
  return h.trim();
}

NodePlace? placeForKnownHost(String host) =>
    kKnownNodePlaces[normalizeNodeHost(host)];

NodePlace? _placeFromCache(String host) {
  final key = normalizeNodeHost(host);
  final geo = GeoIpService.instance.cached(key) ??
      GeoIpService.instance.cached(host.trim());
  if (geo == null) return null;
  return NodePlace.fromGeo(geo);
}

/// True when [place] came from GeoIP / known flag (not a globe placeholder).
bool isResolvedPlace(NodePlace place) {
  final flag = place.flag.trim();
  return flag.isNotEmpty && flag != '🌐' && flag != '🌍';
}

/// Sync place: **known pool first** → GeoIP cache → safe placeholder.
///
/// Never surfaces Marzban ids, bare IPs, or datacenter ops nicknames as title.
NodePlace placeForHost(String host, {int index = 0, String? fallbackLabel}) {
  final known = placeForKnownHost(host);
  if (known != null) return known;

  final cached = _placeFromCache(host);
  if (cached != null) return cached;

  final raw = fallbackLabel?.trim() ?? '';
  if (raw.isNotEmpty &&
      !_isOpsOrGenericLabel(raw) &&
      !_looksLikeDatacenterOpsName(raw) &&
      !_looksLikeIp(raw)) {
    return NodePlace(title: raw, subtitle: normalizeNodeHost(host), flag: '🌐');
  }
  return NodePlace(
    title: 'Сервер ${index + 1}',
    titleEn: 'Server ${index + 1}',
    subtitle: normalizeNodeHost(host),
    flag: '🌐',
  );
}

NodePlace placeForNode(VpnNode node, {int index = 0}) {
  final known = placeForKnownHost(node.host);
  if (known != null) return known;

  final cached = _placeFromCache(node.host);
  if (cached != null) return cached;

  final raw = node.label.isNotEmpty
      ? node.label
      : (node.name.isNotEmpty ? node.name : '');
  if (raw.isEmpty ||
      _isOpsOrGenericLabel(raw) ||
      _looksLikeDatacenterOpsName(raw) ||
      _looksLikeIp(raw)) {
    return NodePlace(
      title: 'Сервер ${index + 1}',
      titleEn: 'Server ${index + 1}',
      subtitle: normalizeNodeHost(node.host),
      flag: '🌐',
    );
  }
  return NodePlace(
    title: raw,
    subtitle: normalizeNodeHost(node.host),
    flag: '🌐',
  );
}

bool _isOpsOrGenericLabel(String raw) {
  final t = raw.trim();
  return RegExp(r'^node[-_\s]?\d+$', caseSensitive: false).hasMatch(t) ||
      RegExp(r'^(Сервер|Server)\s*\d+$', caseSensitive: false).hasMatch(t);
}

bool _looksLikeIp(String raw) {
  final t = normalizeNodeHost(raw);
  if (t.isEmpty) return false;
  // IPv4
  if (RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(t)) return true;
  // Rough IPv6
  if (t.contains(':') && RegExp(r'^[0-9a-fA-F:]+$').hasMatch(t)) return true;
  return false;
}

/// Marzban panel labels are for ops, not end users (e.g. "Yotta Frankfurt").
bool _looksLikeDatacenterOpsName(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return false;
  if (RegExp(r'^(yotta|hetzner|ovh|vultr|digitalocean|linode|aws|gcp)\b',
          caseSensitive: false)
      .hasMatch(t)) {
    return true;
  }
  // "Something City" in Latin letters only — almost always panel nickname.
  if (RegExp(r'^[A-Za-z][A-Za-z0-9._-]*(?:\s+[A-Za-z][A-Za-z0-9._-]*)+$')
      .hasMatch(t)) {
    return true;
  }
  return false;
}

/// Call after obtaining egress IP / node host to populate GeoIP cache.
Future<void> warmGeoCache(String ip, {GeoIpService? service}) async {
  final key = normalizeNodeHost(ip);
  if (key.isEmpty) return;
  final svc = service ?? GeoIpService.instance;
  if (svc.cached(key) != null) return;
  await svc.lookup(key);
}

/// Async resolve: GeoIP lookup then [placeForHost].
Future<NodePlace> resolvePlaceForHost(
  String host, {
  int index = 0,
  String? fallbackLabel,
}) async {
  await warmGeoCache(host);
  return placeForHost(host, index: index, fallbackLabel: fallbackLabel);
}

Future<NodePlace> resolvePlaceForNode(VpnNode node, {int index = 0}) async {
  await warmGeoCache(node.host);
  return placeForNode(node, index: index);
}
