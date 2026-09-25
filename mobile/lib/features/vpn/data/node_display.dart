import '../../../l10n/app_localizations.dart';
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

  String displayTitle(String languageCode) {
    String pick() {
      if (languageCode != 'en') return title;
      final en = titleEn?.trim();
      if (en != null && en.isNotEmpty) return en;
      return englishTitleForProduct(title) ?? title;
    }

    return stripTierRole(pick());
  }

  String displaySubtitle(String languageCode) {
    if (languageCode != 'en') return subtitle;
    final en = subtitleEn?.trim();
    if (en != null && en.isNotEmpty) return en;
    return englishTitleForProduct(subtitle) ?? subtitle;
  }

  factory NodePlace.fromGeo(GeoIpResult geo) {
    final code = geo.countryCode.toUpperCase();
    return NodePlace(
      title: geo.displayCountry('ru'),
      titleEn: code == 'US' ? 'USA' : geo.country,
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
/// `204.11` omitted — gaming TT product label must win over IP-geo.
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
    subtitle: '',
    titleEn: 'USA',
    subtitleEn: '',
    flag: '🇺🇸',
  ),
  '217.60.3.9': NodePlace(
    title: 'Латвия',
    subtitle: 'Низкий пинг',
    titleEn: 'Latvia',
    subtitleEn: 'Low ping',
    flag: '🇱🇻',
  ),
  '107.181.139.193': NodePlace(
    title: 'Индия',
    subtitle: '',
    titleEn: 'India',
    subtitleEn: '',
    flag: '🇮🇳',
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
  title: 'YouTube',
  titleEn: 'YouTube',
  subtitle: '',
  flag: 'youtube',
);

/// Premium gaming TT (DE ping for RF clients) — never country name.
const NodePlace kGamingPremiumPlace = NodePlace(
  title: 'Игровой',
  titleEn: 'Gaming',
  subtitle: '',
  flag: 'gaming',
);

/// Premium India geo (local apps / prices) — country is the product.
const NodePlace kIndiaPremiumPlace = NodePlace(
  title: 'Индия',
  titleEn: 'India',
  subtitle: '',
  flag: '🇮🇳',
);

const String kFlagEurope = '🇱🇻';
const String kFlagUsa = '🇺🇸';
const String kFlagIndia = '🇮🇳';
const String kFlagGlobe = '🌐';
const String kFlagGaming = 'gaming';

/// Visible Free Hy2 row if a live Hy2 node is in the catalog (not on 204.11).
const NodePlace kHysteriaMobilePlace = NodePlace(
  title: 'Латвия',
  titleEn: 'Latvia',
  subtitle: 'Низкий пинг',
  subtitleEn: 'Low ping',
  flag: kFlagEurope,
);

const NodePlace kUsaMobilePlace = NodePlace(
  title: 'США',
  titleEn: 'USA',
  subtitle: '',
  subtitleEn: '',
  flag: kFlagUsa,
);

/// Locations list section for grouping (Auto is separate UI row).
enum LocationSection { premium, general, other }

/// Drop catalog «· Free / · Premium» — country or product name only.
String stripTierRole(String raw) {
  return raw.trim().replaceFirst(
        RegExp(
          r'\s*[·•.\-–—]\s*(Бесплатно|Free|Premium|Премиум)\s*$',
          caseSensitive: false,
        ),
        '',
      );
}

/// English stand-in when catalog copy is Russian and [NodePlace.titleEn] is empty.
String? englishTitleForProduct(String raw) {
  final t = stripTierRole(raw).trim().toLowerCase();
  if (t.isEmpty) return null;
  const map = <String, String>{
    'сша': 'USA',
    'usa': 'USA',
    'латвия': 'Latvia',
    'latvia': 'Latvia',
    'европа': 'Latvia',
    'europe': 'Latvia',
    'индия': 'India',
    'india': 'India',
    'игровой': 'Gaming',
    'gaming': 'Gaming',
    'нидерланды': 'Netherlands',
    'netherlands': 'Netherlands',
    'амстердам': 'Amsterdam',
    'amsterdam': 'Amsterdam',
    'низкий пинг': 'Low ping',
  };
  final mapped = map[t];
  if (mapped != null) return mapped;
  final server = RegExp(r'^сервер\s+(\d+)$').firstMatch(t);
  if (server != null) return 'Server ${server.group(1)}';
  return null;
}

/// Catalog product copy → bilingual place (Free USA/EU, Premium slots).
NodePlace? canonicalPlaceForProductLabel(String raw) {
  final t = stripTierRole(raw).trim().toLowerCase();
  if (t.isEmpty) return null;
  if (t.contains('youtube')) return kYoutubePremiumPlace;
  if (t.contains('игровой') || t.contains('gaming')) return kGamingPremiumPlace;
  if (t.contains('индия') || t.contains('india')) return kIndiaPremiumPlace;
  if (t.contains('сша') ||
      t.contains('united states') ||
      t.contains('usa') ||
      t == 'us') {
    return kUsaMobilePlace;
  }
  if (t.contains('европа') ||
      t.contains('europe') ||
      t.contains('латвия') ||
      t.contains('latvia')) {
    return kHysteriaMobilePlace;
  }
  if (t.contains('нидерланды') || t.contains('netherlands')) {
    return kKnownNodePlaces['185.139.228.192'];
  }
  return null;
}

/// User-facing catalog/home label with English titles attached.
NodePlace placeFromProductLabel(String raw, {String? flag}) {
  final canonical = canonicalPlaceForProductLabel(raw);
  if (canonical != null) return canonical;
  final title = stripTierRole(raw);
  return NodePlace(
    title: title,
    titleEn: englishTitleForProduct(title),
    subtitle: '',
    flag: flag ?? flagForProductLabel(raw),
  );
}

/// Locations / Home blurb when [NodePlace.subtitle] is empty.
String displaySubtitleForNode(VpnNode node, AppL10n l) {
  if (node.isYoutube) return l.regionBlurbYoutube;
  if (node.isGaming) return l.regionBlurbGaming;
  if (node.isGeoIn) return l.regionBlurbIndia;
  return l.regionBlurbFree;
}

/// Strip tier suffixes and reject ops/FQDN labels for Home fallback copy.
String sanitizeHomeLabel(String raw) {
  final t = raw.trim();
  if (t.isEmpty || _isUnsafeUserFacingLabel(t)) return '';
  return stripTierRole(t);
}

/// First catalog node whose host matches [host] (port-normalized).
VpnNode? catalogNodeForHost(Iterable<VpnNode> catalog, String? host) {
  final key = normalizeNodeHost(host ?? '');
  if (key.isEmpty) return null;
  for (final n in catalog) {
    if (normalizeNodeHost(n.host) == key) return n;
  }
  return null;
}

/// Flag for catalog product labels / node.region (not GeoIP).
String flagForNode(VpnNode node, {String? productLabel}) {
  if (node.isYoutube) return 'youtube';
  if (node.isGaming) return kFlagGaming;
  if (node.isGeoIn) return kFlagIndia;
  final region = (node.region ?? '').trim().toLowerCase();
  if (region == 'eu' || region == 'europe') return kFlagEurope;
  if (region == 'us' || region == 'usa') return kFlagUsa;
  if (region == 'in' || region == 'india') return kFlagIndia;
  if (node.isGeoUs) return kFlagUsa;

  final label =
      (productLabel ?? (node.label.isNotEmpty ? node.label : node.name))
          .trim()
          .toLowerCase();
  return flagForProductLabel(label);
}

/// Infer EU/US/IN flag from user-facing catalog copy.
String flagForProductLabel(String label) {
  final t = label.trim().toLowerCase();
  if (t.isEmpty) return kFlagGlobe;
  if (t.contains('игровой') || t.contains('gaming')) return kFlagGaming;
  if (t.contains('индия') || t.contains('india')) return kFlagIndia;
  if (t.contains('латвия') || t.contains('latvia')) return kFlagEurope;
  if (t.contains('европа') || t.contains('europe')) return kFlagEurope;
  if (t.contains('сша') ||
      t.contains('usa') ||
      t.contains('united states') ||
      RegExp(r'\bus\b').hasMatch(t)) {
    return kFlagUsa;
  }
  return kFlagGlobe;
}

/// Unique location flags in Auto pool order (Home Connecting cycle).
List<String> uniqueAutoPoolFlags(Iterable<VpnNode> pool) {
  final seen = <String>{};
  final out = <String>[];
  for (final node in pool) {
    final flag = flagForNode(node);
    if (flag == kFlagGlobe) continue;
    if (seen.add(flag)) out.add(flag);
  }
  if (out.isEmpty) return [kFlagGlobe];
  return out;
}

/// Catalog node that Auto proved, if [winnerId] is still in [catalog].
VpnNode? autoWinnerNode(Iterable<VpnNode> catalog, String? winnerId) {
  if (winnerId == null || winnerId.isEmpty) return null;
  for (final n in catalog) {
    if (n.id == winnerId) return n;
  }
  return null;
}

/// Product flag for Auto on Home and the Locations Auto row.
///
/// Winner uses [placeForNode] so YouTube / Gaming / India / Latvia / USA match.
/// Until prove finishes, both screens use the first Auto-pool flag.
String autoSelectionDisplayFlag({
  required Iterable<VpnNode> catalog,
  String? winnerId,
  List<String>? poolFlags,
}) {
  final winner = autoWinnerNode(catalog, winnerId);
  if (winner != null) return placeForNode(winner).flag;
  final flags = poolFlags ?? uniqueAutoPoolFlags(catalog);
  if (flags.isNotEmpty) return flags.first;
  return kFlagGlobe;
}

/// Which list a route belongs to. Paid sections are not used.
LocationSection locationSectionFor(VpnNode node) {
  final region = (node.region ?? '').trim().toLowerCase();
  final label = (node.label.isNotEmpty ? node.label : node.name).toLowerCase();
  if (region == 'eu' ||
      region == 'europe' ||
      label.contains('европа') ||
      label.contains('europe') ||
      label.contains('латвия') ||
      label.contains('latvia') ||
      region == 'us' ||
      region == 'usa' ||
      node.isGeoUs ||
      label.contains('сша') ||
      label.contains('usa') ||
      label.contains('united states')) {
    return LocationSection.general;
  }
  final flag = flagForNode(node);
  if (flag == kFlagEurope || flag == kFlagUsa) return LocationSection.general;
  return LocationSection.other;
}

int _generalRank(VpnNode node) {
  final flag = flagForNode(node);
  if (flag == kFlagEurope) return 0;
  if (flag == kFlagUsa) return 1;
  return 2;
}

/// Partition online nodes into Premium → General (EU then US) → Other.
Map<LocationSection, List<VpnNode>> groupNodesByLocationSection(
  Iterable<VpnNode> nodes,
) {
  final out = <LocationSection, List<VpnNode>>{
    for (final s in LocationSection.values) s: <VpnNode>[],
  };
  for (final n in nodes) {
    out[locationSectionFor(n)]!.add(n);
  }
  for (final entry in out.entries) {
    entry.value.sort((a, b) {
      if (entry.key == LocationSection.general) {
        final rank = _generalRank(a).compareTo(_generalRank(b));
        if (rank != 0) return rank;
      }
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
    return placeFromProductLabel(raw);
  }

  final known = placeForKnownHost(host);
  if (known != null) return known;

  final cached = _placeFromCache(host);
  if (cached != null) return cached;

  if (raw.isNotEmpty && !_isUnsafeUserFacingLabel(raw)) {
    return placeFromProductLabel(raw);
  }
  return NodePlace(
    title: 'Сервер ${index + 1}',
    titleEn: 'Server ${index + 1}',
    subtitle: '',
    flag: kFlagGlobe,
  );
}

NodePlace placeForNode(VpnNode node, {int index = 0}) {
  // YouTube / gaming / India product labels win over GeoIP.
  if (node.isYoutube) return kYoutubePremiumPlace;
  if (node.isGaming) return kGamingPremiumPlace;
  if (node.isGeoIn) return kIndiaPremiumPlace;
  final raw = node.label.isNotEmpty
      ? node.label
      : (node.name.isNotEmpty ? node.name : '');
  if (raw.isNotEmpty && !_isUnsafeUserFacingLabel(raw)) {
    final fromLabel = canonicalPlaceForProductLabel(raw);
    if (fromLabel != null) return fromLabel;
  }

  if (node.isHysteria) {
    final hyLabel = raw;
    final lowerLabel = hyLabel.toLowerCase();
    if (hyLabel.isNotEmpty &&
        _isSafeProductLabel(hyLabel) &&
        !lowerLabel.contains('европа') &&
        !lowerLabel.contains('europe')) {
      return placeFromProductLabel(
        hyLabel,
        flag: flagForNode(node, productLabel: hyLabel),
      );
    }
    if (node.isGeoUs) {
      return kUsaMobilePlace;
    }
    return kHysteriaMobilePlace;
  }

  // Catalog product labels beat IP-geo known map (EU → not Frankfurt).
  if (raw.isNotEmpty && _isSafeProductLabel(raw)) {
    return placeFromProductLabel(
      raw,
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
  return placeFromProductLabel(
    raw,
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
