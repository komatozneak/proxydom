import 'geo_ip_service.dart';

/// Human-facing labels for the imported line the user picked (ids like `node-185`
/// are ops names and never shown).
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

/// Product categories for nodes that are sold as a role, not a country.
const NodePlace kMediaNodePlace = NodePlace(
  title: 'Медиа-поток',
  titleEn: 'Media stream',
  subtitle: '',
  flag: 'media',
);

const NodePlace kCloudNodePlace = NodePlace(
  title: 'Облачный API',
  titleEn: 'Cloud API',
  subtitle: '',
  flag: 'cloud',
);

const NodePlace kWorkNodePlace = NodePlace(
  title: 'Рабочий узел',
  titleEn: 'Work node',
  subtitle: '',
  flag: 'work',
);

const NodePlace kBackupNodePlace = NodePlace(
  title: 'Резервный канал',
  titleEn: 'Backup channel',
  subtitle: '',
  flag: 'backup',
);

const String kFlagEurope = '🇱🇻';
const String kFlagUsa = '🇺🇸';
const String kFlagIndia = '🇮🇳';
const String kFlagGlobe = '🌐';
const String kFlagMedia = 'media';
const String kFlagCloud = 'cloud';
const String kFlagWork = 'work';
const String kFlagBackup = 'backup';

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

/// Drop the catalog tier suffix — country or product name only.
String stripTierRole(String raw) {
  return raw.trim().replaceFirst(
        RegExp(
          r'\s*[·•.\-–—]\s*(Бесплатно|Free)\s*$',
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
    'игровой': 'Cloud API',
    'gaming': 'Cloud API',
    'медиа': 'Media stream',
    'media': 'Media stream',
    'рабочий': 'Work node',
    'work': 'Work node',
    'резерв': 'Backup channel',
    'backup': 'Backup channel',
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

/// Catalog product copy → bilingual category or country place.
NodePlace? canonicalPlaceForProductLabel(String raw) {
  final t = stripTierRole(raw).trim().toLowerCase();
  if (t.isEmpty) return null;
  if (t.contains('медиа') ||
      t.contains('media') ||
      t.contains('video') ||
      t.contains('stream')) {
    return kMediaNodePlace;
  }
  if (t.contains('игров') ||
      t.contains('gaming') ||
      t.contains('cloud') ||
      t.contains('облак') ||
      t.contains('api')) {
    return kCloudNodePlace;
  }
  if (t.contains('рабоч') ||
      t.contains('work') ||
      t.contains('офис') ||
      t.contains('office')) {
    return kWorkNodePlace;
  }
  if (t.contains('резерв') || t.contains('backup') || t.contains('запасн')) {
    return kBackupNodePlace;
  }
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

/// Strip tier suffixes and reject ops/FQDN labels for Home fallback copy.
String sanitizeHomeLabel(String raw) {
  final t = raw.trim();
  if (t.isEmpty || _isUnsafeUserFacingLabel(t)) return '';
  return stripTierRole(t);
}

/// Infer a category or country flag from user-facing catalog copy.
String flagForProductLabel(String label) {
  final t = label.trim().toLowerCase();
  if (t.isEmpty) return kFlagGlobe;
  if (t.contains('медиа') ||
      t.contains('media') ||
      t.contains('video') ||
      t.contains('stream')) {
    return kFlagMedia;
  }
  if (t.contains('игров') ||
      t.contains('gaming') ||
      t.contains('cloud') ||
      t.contains('облак') ||
      t.contains('api')) {
    return kFlagCloud;
  }
  if (t.contains('рабоч') ||
      t.contains('work') ||
      t.contains('офис') ||
      t.contains('office')) {
    return kFlagWork;
  }
  if (t.contains('резерв') || t.contains('backup') || t.contains('запасн')) {
    return kFlagBackup;
  }
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

/// Sync place: category → product label → known pool → GeoIP → placeholder.
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
      t.toLowerCase().contains('proxydom');
}

/// Hostname / FQDN / ops id — never show in Locations title/subtitle.
bool _looksLikeHostOrFqdn(String raw) {
  final t = normalizeNodeHost(raw);
  if (t.isEmpty) return false;
  if (t.contains('.')) {
    // e.g. node.proxydom.su, example.com
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
