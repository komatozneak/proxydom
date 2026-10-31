import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One site in the Modes «По сайтам» pool (preset or custom).
class SplitTunnelSite {
  const SplitTunnelSite({
    required this.id,
    required this.domain,
    required this.enabled,
    this.label = '',
    this.subtitle = '',
    this.players = const [],
  });

  final String id;
  final String domain;
  final bool enabled;
  final String label;
  final String subtitle;

  /// Player and player-CDN hosts embedded by this site. They travel with the
  /// site: adding [domain] to the direct list without its players is what left
  /// video players asking for the VPN to be turned off.
  final List<String> players;

  bool get isPreset => id.startsWith('preset_');

  SplitTunnelSite copyWith({
    String? id,
    String? domain,
    bool? enabled,
    String? label,
    String? subtitle,
    List<String>? players,
  }) {
    return SplitTunnelSite(
      id: id ?? this.id,
      domain: domain ?? this.domain,
      enabled: enabled ?? this.enabled,
      label: label ?? this.label,
      subtitle: subtitle ?? this.subtitle,
      players: players ?? this.players,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'domain': domain,
        'enabled': enabled,
        'label': label,
        'subtitle': subtitle,
        'players': players,
      };

  factory SplitTunnelSite.fromJson(Map<String, dynamic> json) {
    return SplitTunnelSite(
      id: '${json['id'] ?? ''}',
      domain: '${json['domain'] ?? ''}',
      enabled: json['enabled'] as bool? ?? true,
      label: '${json['label'] ?? ''}',
      subtitle: '${json['subtitle'] ?? ''}',
      players: (json['players'] as List?)
              ?.map((value) => '$value')
              .where((value) => value.isNotEmpty)
              .toList() ??
          const [],
    );
  }
}

/// Result of [normalizeSplitTunnelDomain].
sealed class DomainNormalizeResult {
  const DomainNormalizeResult();
}

class DomainNormalizeOk extends DomainNormalizeResult {
  const DomainNormalizeOk(this.domain);
  final String domain;
}

enum DomainNormalizeErrorKind {
  empty,
  scheme,
  pathOrPort,
  wildcard,
  ipLiteral,
  singleLabel,
  nonAscii,
  duplicate,
}

class DomainNormalizeErr extends DomainNormalizeResult {
  const DomainNormalizeErr(this.kind);
  final DomainNormalizeErrorKind kind;
}

final _ipv4 = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');
final _ipv6ish = RegExp(r'^[0-9a-fA-F:]+$');
final _hostLabel = RegExp(r'^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$');
final _schemePrefix = RegExp(r'^([a-z][a-z0-9+.-]*)://');

/// Trim, lowercase, strip trailing dot and a leading `www.`.
///
/// The field says `example.com`, but people paste the address bar:
/// `https://www.example.com/path?q=1#top`. A site is its host, so the scheme,
/// path, query, fragment and port are dropped. Only http(s) links are accepted;
/// other schemes are not a web address.
DomainNormalizeResult normalizeSplitTunnelDomain(String raw) {
  var s = raw.trim().toLowerCase();
  if (s.isEmpty) {
    return const DomainNormalizeErr(DomainNormalizeErrorKind.empty);
  }
  if (RegExp(r'\s').hasMatch(s)) {
    return const DomainNormalizeErr(DomainNormalizeErrorKind.empty);
  }
  final scheme = _schemePrefix.firstMatch(s);
  if (scheme != null) {
    final name = scheme.group(1)!;
    if (name != 'http' && name != 'https') {
      return const DomainNormalizeErr(DomainNormalizeErrorKind.scheme);
    }
  }
  final host = _siteHostFromInput(s);
  if (host == null) {
    return const DomainNormalizeErr(DomainNormalizeErrorKind.empty);
  }
  s = host;
  if (s.endsWith('.')) {
    s = s.substring(0, s.length - 1);
  }
  if (s.startsWith('www.')) {
    s = s.substring(4);
  }
  if (s.isEmpty) {
    return const DomainNormalizeErr(DomainNormalizeErrorKind.empty);
  }
  if (s.contains('*')) {
    return const DomainNormalizeErr(DomainNormalizeErrorKind.wildcard);
  }
  if (_ipv4.hasMatch(s) || (s.contains(':') && _ipv6ish.hasMatch(s))) {
    return const DomainNormalizeErr(DomainNormalizeErrorKind.ipLiteral);
  }
  if (s.runes.any((r) => r > 127)) {
    return const DomainNormalizeErr(DomainNormalizeErrorKind.nonAscii);
  }
  final labels = s.split('.');
  if (labels.length < 2) {
    return const DomainNormalizeErr(DomainNormalizeErrorKind.singleLabel);
  }
  for (final label in labels) {
    if (!_hostLabel.hasMatch(label)) {
      return const DomainNormalizeErr(DomainNormalizeErrorKind.empty);
    }
  }
  return DomainNormalizeOk(s);
}

/// Upper bound on player hosts stored with one site.
const int kMaxSplitTunnelPlayers = 8;

/// Normalizes player hosts and drops the site itself and its subdomains.
List<String> normalizeSplitTunnelPlayers(
  String siteDomain,
  Iterable<String> raw,
) {
  final site = normalizeSplitTunnelDomain(siteDomain);
  final owner =
      site is DomainNormalizeOk ? site.domain : siteDomain.trim().toLowerCase();
  if (owner.isEmpty) return const [];
  final out = <String>{};
  for (final value in raw) {
    final result = normalizeSplitTunnelDomain(value);
    if (result is! DomainNormalizeOk) continue;
    final domain = result.domain;
    if (domain == owner || domain.endsWith('.$owner')) continue;
    out.add(domain);
    if (out.length >= kMaxSplitTunnelPlayers) break;
  }
  return out.toList()..sort();
}

/// Host from a bare domain, a domain with a path, or an http(s) URL.
String? _siteHostFromInput(String text) {
  final Uri? uri;
  if (_schemePrefix.hasMatch(text)) {
    uri = Uri.tryParse(text);
  } else if (text.startsWith('//')) {
    uri = Uri.tryParse('http:$text');
  } else {
    // A bare `example.com/path` is still a link a person may paste.
    uri = Uri.tryParse('http://$text');
  }
  if (uri == null || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
    return null;
  }
  return uri.host;
}

String _newSiteId() {
  final r = Random.secure();
  final bytes = List<int>.generate(16, (_) => r.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// On-device prefs for Sites-only split tunnel (Phase 1).
class SplitTunnelPrefs {
  SplitTunnelPrefs._();

  static const _sitesKey = 'split_tunnel_custom_sites_v1';
  static const _appliedRevKey = 'split_tunnel_applied_rev_v1';
  static const _draftRevKey = 'split_tunnel_draft_rev_v1';
  static const _osnovnyeKey = 'split_tunnel_osnovnye_v1';
  static const _osnovnyeRfDefaultsKey = 'split_tunnel_osnovnye_rf_defaults_v1';
  static const _osnovnyeV2DefaultsKey = 'split_tunnel_osnovnye_v2_defaults_v1';
  static const _osnovnyeV3DefaultsKey = 'split_tunnel_osnovnye_v3_defaults_v1';
  static const _osnovnyeV4DefaultsKey = 'split_tunnel_osnovnye_v4_defaults_v1';
  static const _disallowedAppsKey = 'split_tunnel_disallowed_apps_v1';
  static const _seededBypassKey = 'split_tunnel_seeded_bypass_v1';
  static const _seededBypassV2Key = 'split_tunnel_seeded_bypass_v2';
  static const _seededBypassV3Key = 'split_tunnel_seeded_bypass_v3';
  static const _seededBypassV4Key = 'split_tunnel_seeded_bypass_v4';
  static const _iosAllOnKey = 'split_tunnel_ios_all_on_v1';

  static Map<String, bool> _osnovnyeDefaults() => {
        for (final c in kOsnovnyeCategories) c.id: c.defaultEnabled,
      };

  static Map<String, bool> _decodeOsnovnyeMap(SharedPreferences prefs) {
    final out = _osnovnyeDefaults();
    final raw = prefs.getString(_osnovnyeKey);
    if (raw == null || raw.isEmpty) return out;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        for (final e in decoded.entries) {
          final id = '${e.key}';
          if (out.containsKey(id)) {
            out[id] = e.value == true;
          }
        }
      }
    } catch (_) {}
    return out;
  }

  /// One-shot: turn ON live RF lists even if an older JSON saved them false.
  static Future<void> _applyRfOsnovnyeDefaultsIfNeeded(
    SharedPreferences prefs,
  ) async {
    if (prefs.getBool(_osnovnyeRfDefaultsKey) == true) return;
    final map = _decodeOsnovnyeMap(prefs);
    var changed = false;
    for (final id in kRfDefaultOnOsnovnyeIds) {
      if (map[id] != true) {
        map[id] = true;
        changed = true;
      }
    }
    if (changed) {
      await prefs.setString(_osnovnyeKey, jsonEncode(map));
      await _bumpDraft(prefs);
    }
    await prefs.setBool(_osnovnyeRfDefaultsKey, true);
  }

  /// One-shot: add v2 categories (Steam / RuTube / Avito / banks / Gosuslugi).
  ///
  /// Does not restore a later user OFF — flag is set after the first apply.
  static Future<void> _applyV2OsnovnyeDefaultsIfNeeded(
    SharedPreferences prefs,
  ) async {
    if (prefs.getBool(_osnovnyeV2DefaultsKey) == true) return;
    final map = _decodeOsnovnyeMap(prefs);
    var changed = false;
    for (final id in kOsnovnyeV2Ids) {
      if (map[id] != true) {
        map[id] = true;
        changed = true;
      }
    }
    if (changed) {
      await prefs.setString(_osnovnyeKey, jsonEncode(map));
      await _bumpDraft(prefs);
    }
    await prefs.setBool(_osnovnyeV2DefaultsKey, true);
  }

  /// One-shot: add MAX sites. Same stickiness as v2.
  static Future<void> _applyV3OsnovnyeDefaultsIfNeeded(
    SharedPreferences prefs,
  ) async {
    if (prefs.getBool(_osnovnyeV3DefaultsKey) == true) return;
    final map = _decodeOsnovnyeMap(prefs);
    var changed = false;
    for (final id in kOsnovnyeV3Ids) {
      if (map[id] != true) {
        map[id] = true;
        changed = true;
      }
    }
    if (changed) {
      await prefs.setString(_osnovnyeKey, jsonEncode(map));
      await _bumpDraft(prefs);
    }
    await prefs.setBool(_osnovnyeV3DefaultsKey, true);
  }

  /// One-shot: popular RU shops/mail/telecom/media/transport ON.
  static Future<void> _applyV4OsnovnyeDefaultsIfNeeded(
    SharedPreferences prefs,
  ) async {
    if (prefs.getBool(_osnovnyeV4DefaultsKey) == true) return;
    final map = _decodeOsnovnyeMap(prefs);
    var changed = false;
    for (final id in kOsnovnyeV4Ids) {
      if (map[id] != true) {
        map[id] = true;
        changed = true;
      }
    }
    if (changed) {
      await prefs.setString(_osnovnyeKey, jsonEncode(map));
      await _bumpDraft(prefs);
    }
    await prefs.setBool(_osnovnyeV4DefaultsKey, true);
  }

  /// Live «Основные» toggles. Popular RU Direct defaults ON.
  static Future<Map<String, bool>> loadOsnovnyeEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    await _applyRfOsnovnyeDefaultsIfNeeded(prefs);
    await _applyV2OsnovnyeDefaultsIfNeeded(prefs);
    await _applyV3OsnovnyeDefaultsIfNeeded(prefs);
    await _applyV4OsnovnyeDefaultsIfNeeded(prefs);
    return _decodeOsnovnyeMap(prefs);
  }

  /// iOS: one-shot turn ON every Sites «Основные» row that is still off.
  ///
  /// NoVPN UI is hidden on iOS; this keeps excludedRoutes useful in the
  /// background. Runs once per install; later toggles stick.
  static Future<bool> ensureIosSitesAllEnabledIfNeeded() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return false;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_iosAllOnKey) == true) return false;
    final map = await loadOsnovnyeEnabled();
    var changed = false;
    for (final c in kOsnovnyeCategories) {
      if (map[c.id] != true) {
        map[c.id] = true;
        changed = true;
      }
    }
    if (changed) {
      await prefs.setString(_osnovnyeKey, jsonEncode(map));
      await _bumpDraft(prefs);
    }
    await prefs.setBool(_iosAllOnKey, true);
    return changed;
  }

  static Future<void> setOsnovnyeEnabled(String id, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    final map = await loadOsnovnyeEnabled();
    if (!map.containsKey(id)) return;
    map[id] = value;
    await prefs.setString(_osnovnyeKey, jsonEncode(map));
    await _bumpDraft(prefs);
  }

  static Future<int> osnovnyeEnabledCount() async {
    final map = await loadOsnovnyeEnabled();
    return map.values.where((v) => v).length;
  }

  /// Packages excluded from VPN TUN (bypass).
  static Future<Set<String>> loadDisallowedPackages() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_disallowedAppsKey) ?? const [];
    return raw.where((p) => p.trim().isNotEmpty).toSet();
  }

  static Future<void> setDisallowedPackage(
      String packageName, bool bypass) async {
    final prefs = await SharedPreferences.getInstance();
    final set = await loadDisallowedPackages();
    final pkg = packageName.trim();
    if (pkg.isEmpty) return;
    if (bypass) {
      set.add(pkg);
    } else {
      set.remove(pkg);
    }
    await prefs.setStringList(_disallowedAppsKey, set.toList()..sort());
    await _bumpDraft(prefs);
  }

  /// Once per install: exclude curated RU apps that are actually installed.
  ///
  /// Apps path (`addDisallowedApplication`) works on Hy2. Native apps that
  /// skip DNS (Yandex Go, banks) stay here — Sites suffixes do not cover them.
  /// v1 never re-runs after [_seededBypassKey] so a user off-toggle sticks.
  /// v2 adds VK / Ozon / WB once without restoring packages turned off after v1.
  static Future<bool> seedDefaultBypassIfNeeded(
    Iterable<String> installedPackages,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final installed = installedPackages
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toSet();
    var addedAny = false;

    if (prefs.getBool(_seededBypassKey) != true) {
      final toAdd = kDefaultBypassPackages.intersection(installed);
      if (toAdd.isNotEmpty) {
        final current = await loadDisallowedPackages();
        current.addAll(toAdd);
        await prefs.setStringList(_disallowedAppsKey, current.toList()..sort());
        await _bumpDraft(prefs);
        addedAny = true;
      }
      await prefs.setBool(_seededBypassKey, true);
    }

    if (prefs.getBool(_seededBypassV2Key) != true) {
      final current = await loadDisallowedPackages();
      final toAdd =
          kDefaultBypassPackagesV2.intersection(installed).difference(current);
      if (toAdd.isNotEmpty) {
        current.addAll(toAdd);
        await prefs.setStringList(_disallowedAppsKey, current.toList()..sort());
        await _bumpDraft(prefs);
        addedAny = true;
      }
      await prefs.setBool(_seededBypassV2Key, true);
    }

    if (prefs.getBool(_seededBypassV3Key) != true) {
      final current = await loadDisallowedPackages();
      final toAdd =
          kDefaultBypassPackagesV3.intersection(installed).difference(current);
      if (toAdd.isNotEmpty) {
        current.addAll(toAdd);
        await prefs.setStringList(_disallowedAppsKey, current.toList()..sort());
        await _bumpDraft(prefs);
        addedAny = true;
      }
      await prefs.setBool(_seededBypassV3Key, true);
    }

    if (prefs.getBool(_seededBypassV4Key) != true) {
      final current = await loadDisallowedPackages();
      final toAdd =
          kDefaultBypassPackagesV4.intersection(installed).difference(current);
      if (toAdd.isNotEmpty) {
        current.addAll(toAdd);
        await prefs.setStringList(_disallowedAppsKey, current.toList()..sort());
        await _bumpDraft(prefs);
        addedAny = true;
      }
      await prefs.setBool(_seededBypassV4Key, true);
    }

    return addedAny;
  }

  static Future<List<SplitTunnelSite>> loadSites() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sitesKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => SplitTunnelSite.fromJson(Map<String, dynamic>.from(e)))
          .where((s) => s.id.isNotEmpty && s.domain.isNotEmpty)
          .map(
            (s) => s.copyWith(
              players: normalizeSplitTunnelPlayers(s.domain, s.players),
            ),
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> saveSites(List<SplitTunnelSite> sites) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _sitesKey,
      jsonEncode(sites.map((s) => s.toJson()).toList()),
    );
    await _bumpDraft(prefs);
  }

  static Future<DomainNormalizeResult> addSite({
    required String domain,
    String label = '',
    bool enabled = true,
    List<String> players = const [],
  }) async {
    final normalized = normalizeSplitTunnelDomain(domain);
    if (normalized is! DomainNormalizeOk) return normalized;
    final sites = await loadSites();
    if (sites.any((s) => s.domain == normalized.domain)) {
      return const DomainNormalizeErr(DomainNormalizeErrorKind.duplicate);
    }
    final next = SplitTunnelSite(
      id: _newSiteId(),
      domain: normalized.domain,
      label: label.trim(),
      enabled: enabled,
      players: normalizeSplitTunnelPlayers(normalized.domain, players),
    );
    await saveSites([...sites, next]);
    return normalized;
  }

  /// Returns false if domain invalid or duplicate of another id.
  static Future<bool> updateSite(SplitTunnelSite site) async {
    final normalized = normalizeSplitTunnelDomain(site.domain);
    if (normalized is! DomainNormalizeOk) return false;
    final sites = await loadSites();
    final idx = sites.indexWhere((s) => s.id == site.id);
    if (idx < 0) return false;
    if (sites.any((s) => s.id != site.id && s.domain == normalized.domain)) {
      return false;
    }
    final copy = [...sites];
    copy[idx] = site.copyWith(
      domain: normalized.domain,
      players: normalizeSplitTunnelPlayers(normalized.domain, site.players),
    );
    await saveSites(copy);
    return true;
  }

  static Future<void> deleteSite(String id) async {
    final sites = await loadSites();
    await saveSites(sites.where((s) => s.id != id).toList());
  }

  /// Enabled domains for routing: custom (non-preset) sites + Основные.
  static Future<List<String>> enabledDomainSuffixes() async {
    final sites = await loadSites();
    final out = <String>{};
    for (final s in sites.where((s) => s.enabled && !s.isPreset)) {
      out.add(s.domain);
      out.addAll(s.players);
    }
    final cats = await loadOsnovnyeEnabled();
    for (final c in kOsnovnyeCategories) {
      if (cats[c.id] != true) continue;
      out.addAll(c.domains);
    }
    return out.toList()..sort();
  }

  /// User-entered exact hostnames for iOS. No suffix or implicit `www` expansion.
  static Future<List<String>> enabledIosCustomResolutionHosts() async {
    final sites = await loadSites();
    final out = <String>{};
    for (final s in sites.where((s) => s.enabled && !s.isPreset)) {
      final d = s.domain.trim().toLowerCase();
      if (d.isEmpty) continue;
      out.add(d);
      out.addAll(s.players);
    }
    return out.toList()..sort();
  }

  /// Selected bundled exact hosts for iOS DNS→`excludedRoutes`.
  static Future<List<String>> enabledIosCatalogResolutionHosts() async {
    final out = <String>{};
    final cats = await loadOsnovnyeEnabled();
    for (final c in kOsnovnyeCategories) {
      if (cats[c.id] != true) continue;
      out.addAll(c.resolutionHostsForIos);
    }
    return out.toList()..sort();
  }

  static Future<bool> hasPendingChanges() async {
    final prefs = await SharedPreferences.getInstance();
    final applied = prefs.getInt(_appliedRevKey) ?? 0;
    final draft = prefs.getInt(_draftRevKey) ?? 0;
    return draft != applied;
  }

  /// Call after VPN successfully starts with current prefs.
  static Future<void> markApplied() async {
    final prefs = await SharedPreferences.getInstance();
    final draft = prefs.getInt(_draftRevKey) ?? 0;
    await prefs.setInt(_appliedRevKey, draft);
  }

  static Future<void> bumpDraftRev() async {
    final prefs = await SharedPreferences.getInstance();
    await _bumpDraft(prefs);
  }

  static Future<void> _bumpDraft(SharedPreferences prefs) async {
    final draft = (prefs.getInt(_draftRevKey) ?? 0) + 1;
    await prefs.setInt(_draftRevKey, draft);
  }

  /// Drop legacy Modes `preset_*` rows from disk (once per session / reload).
  static Future<int> purgePresetSites() async {
    final sites = await loadSites();
    final customs = sites.where((s) => !s.isPreset).toList();
    if (customs.length == sites.length) return 0;
    // Persist without bumping draft — migration, not a user edit.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _sitesKey,
      jsonEncode(customs.map((s) => s.toJson()).toList()),
    );
    return sites.length - customs.length;
  }
}

/// Packages added by the v2 Apps seed (VK / Ozon / WB).
///
/// v1 installs already seeded taxi / banks / Gosuslugi; v2 must not restore
/// those if the user turned them off.
const kDefaultBypassPackagesV2 = <String>{
  'com.vkontakte.android',
  'com.vk.android',
  'ru.ozon.app.android',
  'com.wildberries.ru',
};

/// Packages added by the v3 Apps seed (MAX messenger). Android-only Apps tab.
const kDefaultBypassPackagesV3 = <String>{
  'ru.oneme.app',
};

/// v4: popular RU apps that skip DNS (shops, maps, mail/OK, media, telecom).
const kDefaultBypassPackagesV4 = <String>{
  'ru.avito',
  'ru.rutube.app',
  'com.valvesoftware.android.steam.community',
  'ru.vk.store',
  'ru.dublgis.dgismobile',
  'ru.ok.android',
  'ru.mail.mailapp',
  'ru.yandex.yandexmaps',
  'com.yandex.browser',
  'ru.yandex.searchplugin',
  'ru.ivi.client',
  'ru.more.play',
  'ru.dns.shop.android',
  'ru.sberbank.sbermarket',
  'ru.kuper',
  'ru.cian.main',
  'ru.gazprombank.android.mobilebank.app',
  'ru.mts.mymts',
  'ru.megafon.mlk',
  'ru.beeline.services',
  'ru.tele2.mytele2',
  'ru.rzd.rzd',
};

/// Curated TUN-exclude packages. Only seeded when the package is installed.
const kDefaultBypassPackages = <String>{
  'ru.yandex.taxi',
  'ru.yandex.android.taxi',
  'ru.yandex.ytaxi',
  'ru.yandex.taximeter',
  'ru.sberbankmobile',
  'ru.sberbank.sberbankid',
  'com.idamob.tinkoff.android',
  'ru.alfabank.mobile.android',
  'ru.vtb24.mobilebanking.android',
  'ru.gosuslugi.mobile',
  ...kDefaultBypassPackagesV2,
  ...kDefaultBypassPackagesV3,
  ...kDefaultBypassPackagesV4,
};

/// Live RF site lists that default ON (suffix → Hy2 direct / iOS exclude).
const kRfDefaultOnOsnovnyeIds = <String>{
  'vk',
  'yandex',
  'ozon',
  'wb',
  'steam',
  'rutube',
  'avito',
  'banks',
  'gosuslugi',
  'max',
  'shops',
  'mailok',
  'telecom',
  'media',
  'transport',
};

/// Category ids shipped in osnovnye v2 (one-shot migrate).
const kOsnovnyeV2Ids = <String>{
  'steam',
  'rutube',
  'avito',
  'banks',
  'gosuslugi',
};

/// Category ids shipped in osnovnye v3.
const kOsnovnyeV3Ids = <String>{
  'max',
};

/// Remaining popular RU rows (shops / Mail·OK / telecom / media / transport).
const kOsnovnyeV4Ids = <String>{
  'shops',
  'mailok',
  'telecom',
  'media',
  'transport',
};

/// One row under Sites → Основные.
class OsnovnyeCategory {
  const OsnovnyeCategory({
    required this.id,
    required this.labelRu,
    required this.labelEn,
    required this.badge,
    required this.domains,
    this.iosResolutionHosts = const [],
    this.defaultEnabled = false,
  });

  final String id;
  final String labelRu;
  final String labelEn;
  final String badge;
  /// Android hyDialer suffixes (may imply subdomain matching in Go).
  final List<String> domains;
  /// Exact hostnames for iOS DNS→`excludedRoutes` (apex ≠ CDN). Empty → [domains].
  final List<String> iosResolutionHosts;
  final bool defaultEnabled;

  String label(String languageCode) => languageCode == 'en' ? labelEn : labelRu;

  /// Hosts to resolve on iOS at connect time.
  List<String> get resolutionHostsForIos =>
      iosResolutionHosts.isNotEmpty ? iosResolutionHosts : domains;
}

/// Live Hy2 suffix lists. Geosite ru/gov placeholders were removed — no matcher.
const kOsnovnyeCategories = <OsnovnyeCategory>[
  OsnovnyeCategory(
    id: 'vk',
    labelRu: 'VK',
    labelEn: 'VK',
    badge: 'VK',
    defaultEnabled: true,
    domains: [
      'vk.com',
      'vk.ru',
      'vk.me',
      'vkontakte.ru',
      'userapi.com',
      'vkuseraudio.net',
      'vkuserphoto.ru',
      'vk-cdn.net',
      'vk-cdn.me',
    ],
  ),
  OsnovnyeCategory(
    id: 'yandex',
    labelRu: 'Сервисы Яндекса',
    labelEn: 'Yandex services',
    badge: 'YA',
    defaultEnabled: true,
    domains: [
      'yandex.ru',
      'yandex.com',
      'yandex.net',
      'ya.ru',
      'yandex.by',
      'yandex.kz',
      'yandex.uz',
      'yandexcloud.net',
      'yastatic.net',
      'kinopoisk.ru',
      'dzen.ru',
      'dzenstatic.ru',
    ],
  ),
  OsnovnyeCategory(
    id: 'ozon',
    labelRu: 'Ozon',
    labelEn: 'Ozon',
    badge: 'OZ',
    defaultEnabled: true,
    domains: ['ozon.ru', 'ozon.com', 'ozone.ru', 'ozonusercontent.com'],
  ),
  OsnovnyeCategory(
    id: 'wb',
    labelRu: 'Wildberries',
    labelEn: 'Wildberries',
    badge: 'WB',
    defaultEnabled: true,
    domains: ['wildberries.ru', 'wb.ru', 'wbbasket.ru', 'wbstatic.net'],
  ),
  OsnovnyeCategory(
    id: 'steam',
    labelRu: 'Steam',
    labelEn: 'Steam',
    badge: 'ST',
    defaultEnabled: true,
    domains: [
      'steampowered.com',
      'steamcommunity.com',
      'steamstatic.com',
      'steamcontent.com',
      'steamusercontent.com',
      'steamserver.net',
      'valvesoftware.com',
      'dota2.com',
      'steam-chat.com',
    ],
  ),
  OsnovnyeCategory(
    id: 'rutube',
    labelRu: 'RuTube',
    labelEn: 'RuTube',
    badge: 'RT',
    defaultEnabled: true,
    domains: ['rutube.ru'],
    iosResolutionHosts: [
      'rutube.ru',
      'www.rutube.ru',
      'static.rutube.ru',
      'pic.rutube.ru',
      'preview.rutube.ru',
    ],
  ),
  OsnovnyeCategory(
    id: 'avito',
    labelRu: 'Avito',
    labelEn: 'Avito',
    badge: 'AV',
    defaultEnabled: true,
    domains: ['avito.ru', 'avito.st'],
    iosResolutionHosts: [
      'avito.ru',
      'www.avito.ru',
      'm.avito.ru',
      'api.avito.ru',
      'avito.st',
    ],
  ),
  OsnovnyeCategory(
    id: 'max',
    labelRu: 'MAX',
    labelEn: 'MAX',
    badge: 'MX',
    defaultEnabled: true,
    // v2fly mailru-group Messenger MAX + public API hosts. No okcdn.ru / apptracer.
    domains: ['max.ru', 'oneme.ru'],
    iosResolutionHosts: [
      'max.ru',
      'www.max.ru',
      'web.max.ru',
      'api.max.ru',
      'ws-api.max.ru',
      'oneme.ru',
    ],
  ),
  OsnovnyeCategory(
    id: 'banks',
    labelRu: 'Банки',
    labelEn: 'Banks',
    badge: 'BK',
    defaultEnabled: true,
    domains: [
      'sberbank.ru',
      'sber.ru',
      'sbrf.ru',
      'sberbank.com',
      'sberpay.ru',
      'tbank.ru',
      'tinkoff.ru',
      't-bank.ru',
      'alfabank.ru',
      'alfa-bank.ru',
      'alfabank.st',
      'vtb.ru',
      'gazprombank.ru',
      'gpb.ru',
      'psbank.ru',
      'psb.ru',
      'raiffeisen.ru',
      'nspk.ru',
      'mironline.ru',
      'privetmir.ru',
      'yoomoney.ru',
      'yoomoney.tech',
    ],
  ),
  OsnovnyeCategory(
    id: 'gosuslugi',
    labelRu: 'Госуслуги',
    labelEn: 'Gosuslugi',
    badge: 'GU',
    defaultEnabled: true,
    domains: [
      'gosuslugi.ru',
      'gosuslugi.org',
      'gu-st.ru',
      'nalog.ru',
      'nalog.gov.ru',
      'mos.ru',
      'emias.info',
      'pfrf.ru',
      'sfr.gov.ru',
      'rosreestr.ru',
      'rosreestr.gov.ru',
      'kadastr.ru',
    ],
  ),
  OsnovnyeCategory(
    id: 'shops',
    labelRu: 'Магазины',
    labelEn: 'Shops',
    badge: 'SH',
    defaultEnabled: true,
    domains: [
      'rustore.ru',
      'vkstore.ru',
      'dns-shop.ru',
      'dns-shop.st',
      'kuper.ru',
      'kupercdn.ru',
      'sbermarket.ru',
      'cian.ru',
      'cdn-cian.ru',
      'lamoda.ru',
      'megamarket.ru',
    ],
  ),
  OsnovnyeCategory(
    id: 'mailok',
    labelRu: 'Mail и ОК',
    labelEn: 'Mail and OK',
    badge: 'OK',
    defaultEnabled: true,
    domains: [
      'mail.ru',
      'ok.ru',
      'ok.me',
      'okcdn.ru',
    ],
  ),
  OsnovnyeCategory(
    id: 'telecom',
    labelRu: 'Связь',
    labelEn: 'Telecom',
    badge: 'TL',
    defaultEnabled: true,
    domains: [
      'mts.ru',
      'megafon.ru',
      'beeline.ru',
      't2.ru',
      'tele2.ru',
      'rt.ru',
      'rostelecom.ru',
      'dom.ru',
    ],
  ),
  OsnovnyeCategory(
    id: 'media',
    labelRu: 'Кино',
    labelEn: 'Video',
    badge: 'TV',
    defaultEnabled: true,
    domains: [
      'ivi.ru',
      'ivi-cdn.ru',
      'okko.tv',
      'okko.sport',
      'wink.ru',
      'premier.one',
      'start.ru',
    ],
  ),
  OsnovnyeCategory(
    id: 'transport',
    labelRu: 'Карты и дорога',
    labelEn: 'Maps and travel',
    badge: 'MP',
    defaultEnabled: true,
    domains: [
      '2gis.ru',
      '2gis.com',
      'rzd.ru',
      'aeroflot.ru',
      's7.ru',
      'whoosh.bike',
      'delimobil.ru',
      'samokat.ru',
    ],
  ),
];
