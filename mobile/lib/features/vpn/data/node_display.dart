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
/// EU primary IPs (`204…` / `217…`) intentionally omitted — catalog label
/// («Европа · основной») must win over IP-geo Frankfurt.
const Map<String, NodePlace> kKnownNodePlaces = {
  '185.139.228.192': NodePlace(
    title: 'Нидерланды',
    subtitle: 'Амстердам',
    titleEn: 'Netherlands',
    subtitleEn: 'Amsterdam',
    flag: '🇳🇱',
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

/// Product label for YouTube / Premium egress (never country name).
const NodePlace kYoutubePremiumPlace = NodePlace(
  title: 'Premium · YouTube',
  titleEn: 'Premium · YouTube',
  subtitle: '',
  flag: '👑',
);

const String kFlagEurope = '🇪🇺';
const String kFlagUsa = '🇺🇸';
const String kFlagGlobe = '🌐';

/// Locations list section for grouping (Auto is separate UI row).
enum LocationSection { premium, europe, usa, other }

/// Flag for catalog product labels / node.region (not GeoIP).
String flagForNode(VpnNode node, {String? productLabel}) {
  if (node.isYoutube) return '👑';
  final region = (node.region ?? '').trim().toLowerCase();
  if (region == 'eu' || region == 'europe') return kFlagEurope;
  if (region == 'us' || region == 'usa') return kFlagUsa;
  if (node.isGeoUs) return kFlagUsa;

  final label = (productLabel ??
          (node.label.isNotEmpty ? node.label : node.name))
      .trim()
      .toLowerCase();
  return flagForProductLabel(label);
}

/// Infer EU/US flag from user-facing catalog copy.
String flagForProductLabel(String label) {
  final t = label.trim().toLowerCase();
  if (t.isEmpty) return kFlagGlobe;
  if (t.contains('европа') || t.contains('europe')) return kFlagEurope;
  if (t.contains('сша') ||
      t.contains('usa') ||
      t.contains('united states') ||
      RegExp(r'\bus\b').hasMatch(t)) {
    return kFlagUsa;
  }
  return kFlagGlobe;
}

/// Which Locations section a node belongs to (first match wins).
LocationSection locationSectionFor(VpnNode node) {
  if (node.isYoutube || node.requiresPremium) return LocationSection.premium;
  final region = (node.region ?? '').trim().toLowerCase();
  final label = (node.label.isNotEmpty ? node.label : node.name).toLowerCase();
  if (region == 'eu' ||
      region == 'europe' ||
      label.contains('европа') ||
      label.contains('europe')) {
    return LocationSection.europe;
  }
  if (region == 'us' ||
      region == 'usa' ||
      node.isGeoUs ||
      label.contains('сша') ||
      label.contains('usa') ||
      label.contains('united states')) {
    return LocationSection.usa;
  }
  // Fallback: product flag heuristics.
  final flag = flagForNode(node);
  if (flag == kFlagEurope) return LocationSection.europe;
  if (flag == kFlagUsa) return LocationSection.usa;
  return LocationSection.other;
}

/// Partition online nodes into Premium → Europe → USA → Other (stable by label).
Map<LocationSection, List<VpnNode>> groupNodesByLocationSection(
  Iterable<VpnNode> nodes,
) {
  final out = <LocationSection, List<VpnNode>>{
    for (final s in LocationSection.values) s: <VpnNode>[],
  };
  for (final n in nodes) {
    out[locationSectionFor(n)]!.add(n);
  }
  for (final list in out.values) {
    list.sort((a, b) {
      final la = a.label.isNotEmpty ? a.label : a.name;
      final lb = b.label.isNotEmpty ? b.label : b.name;
      return la.toLowerCase().compareTo(lb.toLowerCase());
    });
  }
  return out;
}

/// Sync place: YouTube → product label → known pool → GeoIP → placeholder.
///
/// Never surfaces hostnames, FQDNs, Marzban ids, bare IPs, or ops nicknames.
NodePlace placeForHost(String host, {int index = 0, String? fallbackLabel}) {
  final raw = fallbackLabel?.trim() ?? '';
  if (raw.isNotEmpty && _isSafeProductLabel(raw)) {
    return NodePlace(
      title: raw,
      subtitle: '',
      flag: flagForProductLabel(raw),
    );
  }

  final known = placeForKnownHost(host);
  if (known != null) return known;

  final cached = _placeFromCache(host);
  if (cached != null) return cached;

  if (raw.isNotEmpty && !_isUnsafeUserFacingLabel(raw)) {
    return NodePlace(
      title: raw,
      subtitle: '',
      flag: flagForProductLabel(raw),
    );
  }
  return NodePlace(
    title: 'Сервер ${index + 1}',
    titleEn: 'Server ${index + 1}',
    subtitle: '',
    flag: kFlagGlobe,
  );
}

NodePlace placeForNode(VpnNode node, {int index = 0}) {
  // YouTube path wins over known GeoIP map (e.g. AL IP must not say «Албания»).
  if (node.isYoutube) return kYoutubePremiumPlace;

  final raw = node.label.isNotEmpty
      ? node.label
      : (node.name.isNotEmpty ? node.name : '');
  // Catalog product labels beat IP-geo known map (EU → not Frankfurt).
  if (raw.isNotEmpty && _isSafeProductLabel(raw)) {
    return NodePlace(
      title: raw,
      subtitle: '',
      flag: flagForNode(node, productLabel: raw),
    );
  }

  final known = placeForKnownHost(node.host);
  if (known != null) return known;

  final cached = _placeFromCache(node.host);
  if (cached != null) return cached;

  if (raw.isEmpty || _isUnsafeUserFacingLabel(raw)) {
    return NodePlace(
      title: 'Сервер ${index + 1}',
      titleEn: 'Server ${index + 1}',
      subtitle: '',
      flag: flagForNode(node),
    );
  }
  return NodePlace(
    title: raw,
    subtitle: '',
    flag: flagForNode(node, productLabel: raw),
  );
}

/// User-facing catalog copy (Cyrillic / «Region · role»), not ops/FQDN.
bool _isSafeProductLabel(String raw) {
  final t = raw.trim();
  if (t.isEmpty || _isUnsafeUserFacingLabel(t)) return false;
  // Cyrillic product names: «Европа · основной», «США · …»
  if (RegExp(r'[А-Яа-яЁё]').hasMatch(t)) return true;
  // Latin product with middle-dot separator (EN catalog).
  if (t.contains('·') || t.contains(' - ')) return true;
  return false;
}

bool _isUnsafeUserFacingLabel(String raw) {
  return _isOpsOrGenericLabel(raw) ||
      _looksLikeDatacenterOpsName(raw) ||
      _looksLikeIp(raw) ||
      _looksLikeHostOrFqdn(raw);
}

bool _isOpsOrGenericLabel(String raw) {
  final t = raw.trim();
  return RegExp(r'^node[-_\s]?\d+$', caseSensitive: false).hasMatch(t) ||
      RegExp(r'^(Сервер|Server)\s*\d+$', caseSensitive: false).hasMatch(t) ||
      RegExp(r'^tt[-_]', caseSensitive: false).hasMatch(t) ||
      t.toLowerCase().contains('teremokconnect');
}

/// Hostname / FQDN / ops id — never show in Locations title/subtitle.
bool _looksLikeHostOrFqdn(String raw) {
  final t = normalizeNodeHost(raw);
  if (t.isEmpty) return false;
  if (t.contains('.')) {
    // e.g. tt-us.teremokconnect.online, example.com
    return true;
  }
  if (RegExp(r'^tt[-_]', caseSensitive: false).hasMatch(t)) return true;
  return false;
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
