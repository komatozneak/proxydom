import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// One site in the Modes «По сайтам» pool (preset or custom).
class SplitTunnelSite {
  const SplitTunnelSite({
    required this.id,
    required this.domain,
    required this.enabled,
    this.label = '',
    this.subtitle = '',
  });

  final String id;
  final String domain;
  final bool enabled;
  final String label;
  final String subtitle;

  bool get isPreset => id.startsWith('preset_');

  SplitTunnelSite copyWith({
    String? id,
    String? domain,
    bool? enabled,
    String? label,
    String? subtitle,
  }) {
    return SplitTunnelSite(
      id: id ?? this.id,
      domain: domain ?? this.domain,
      enabled: enabled ?? this.enabled,
      label: label ?? this.label,
      subtitle: subtitle ?? this.subtitle,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'domain': domain,
        'enabled': enabled,
        'label': label,
        'subtitle': subtitle,
      };

  factory SplitTunnelSite.fromJson(Map<String, dynamic> json) {
    return SplitTunnelSite(
      id: '${json['id'] ?? ''}',
      domain: '${json['domain'] ?? ''}',
      enabled: json['enabled'] as bool? ?? true,
      label: '${json['label'] ?? ''}',
      subtitle: '${json['subtitle'] ?? ''}',
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

/// Trim, lowercase, strip trailing dot; reject schemes/paths/IPs/wildcards.
DomainNormalizeResult normalizeSplitTunnelDomain(String raw) {
  var s = raw.trim().toLowerCase();
  if (s.isEmpty) {
    return const DomainNormalizeErr(DomainNormalizeErrorKind.empty);
  }
  if (s.contains('://') ||
      s.startsWith('http:') ||
      s.startsWith('https:')) {
    return const DomainNormalizeErr(DomainNormalizeErrorKind.scheme);
  }
  if (s.contains('/') ||
      s.contains('?') ||
      s.contains('#') ||
      s.contains(':')) {
    return const DomainNormalizeErr(DomainNormalizeErrorKind.pathOrPort);
  }
  if (s.contains('*')) {
    return const DomainNormalizeErr(DomainNormalizeErrorKind.wildcard);
  }
  if (s.endsWith('.')) {
    s = s.substring(0, s.length - 1);
  }
  if (s.isEmpty) {
    return const DomainNormalizeErr(DomainNormalizeErrorKind.empty);
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

String _newSiteId() {
  final r = Random.secure();
  final bytes = List<int>.generate(16, (_) => r.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// On-device prefs for Sites-only split tunnel (Phase 1).
class SplitTunnelPrefs {
  SplitTunnelPrefs._();

  static const _bundledRuKey = 'split_tunnel_bundled_ru_v1';
  static const _sitesKey = 'split_tunnel_custom_sites_v1';
  static const _appliedRevKey = 'split_tunnel_applied_rev_v1';
  static const _draftRevKey = 'split_tunnel_draft_rev_v1';

  /// Default ON — preserves existing RU `.srs` direct behavior.
  static Future<bool> isBundledRuEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_bundledRuKey) ?? true;
  }

  static Future<void> setBundledRuEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_bundledRuKey, value);
    await _bumpDraft(prefs);
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
    copy[idx] = site.copyWith(domain: normalized.domain);
    await saveSites(copy);
    return true;
  }

  static Future<void> deleteSite(String id) async {
    final sites = await loadSites();
    await saveSites(sites.where((s) => s.id != id).toList());
  }

  /// Enabled domains for routing, with CDN aliases expanded (YouTube → googlevideo…).
  static Future<List<String>> enabledDomainSuffixes() async {
    final sites = await loadSites();
    final out = <String>{};
    for (final s in sites.where((s) => s.enabled)) {
      out.add(s.domain);
      final aliases = kSplitTunnelDomainAliases[s.domain];
      if (aliases != null) out.addAll(aliases);
    }
    return out.toList()..sort();
  }

  /// DC / CDN IP ranges for presets that bypass DNS (Telegram apps hit IPs directly).
  static Future<List<String>> enabledProxyIpCidrs() async {
    final sites = await loadSites();
    final out = <String>{};
    for (final s in sites.where((s) => s.enabled)) {
      final cidrs = kSplitTunnelProxyIpCidrs[s.domain];
      if (cidrs != null) out.addAll(cidrs);
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

  /// Exposed so [VpnRouteModePrefs] can share the pending-reconnect counter.
  static Future<void> bumpDraftRev() async {
    final prefs = await SharedPreferences.getInstance();
    await _bumpDraft(prefs);
  }

  static Future<void> _bumpDraft(SharedPreferences prefs) async {
    final draft = (prefs.getInt(_draftRevKey) ?? 0) + 1;
    await prefs.setInt(_draftRevKey, draft);
  }

  /// Seed curated presets (and refresh labels/subtitles) without wiping customs.
  static Future<void> ensurePresetSites() async {
    final existing = await loadSites();
    final byDomain = {for (final s in existing) s.domain: s};
    final presetDomains = {for (final p in kSplitTunnelPresets) p.domain};
    var changed = false;
    final next = <SplitTunnelSite>[];

    for (final preset in kSplitTunnelPresets) {
      final prev = byDomain[preset.domain];
      if (prev == null) {
        next.add(
          SplitTunnelSite(
            id: 'preset_${preset.domain.replaceAll('.', '_')}',
            domain: preset.domain,
            label: preset.label,
            subtitle: preset.subtitle,
            enabled: preset.defaultEnabled,
          ),
        );
        changed = true;
        continue;
      }
      final presetId = 'preset_${preset.domain.replaceAll('.', '_')}';
      final refreshed = prev.copyWith(
        id: prev.isPreset ? prev.id : presetId,
        label: preset.label,
        subtitle: preset.subtitle,
      );
      if (refreshed.label != prev.label ||
          refreshed.subtitle != prev.subtitle ||
          refreshed.id != prev.id) {
        changed = true;
      }
      next.add(refreshed);
    }

    for (final s in existing) {
      if (presetDomains.contains(s.domain)) continue;
      next.add(s);
    }

    if (changed || next.length != existing.length) {
      await saveSites(next);
    }
  }
}

/// Curated domain suffixes shown on Modes (local seed, no remote API).
class SplitTunnelPreset {
  const SplitTunnelPreset({
    required this.domain,
    required this.label,
    this.subtitle = '',
    this.defaultEnabled = true,
  });

  final String domain;
  final String label;
  final String subtitle;
  final bool defaultEnabled;
}

const kSplitTunnelPresets = <SplitTunnelPreset>[
  SplitTunnelPreset(
    domain: 'cloudflare.com',
    label: 'Cloudflare',
    subtitle: 'Большинство неработающих сайтов',
  ),
  SplitTunnelPreset(
    domain: 'youtube.com',
    label: 'YouTube',
    subtitle: 'YouTube и сервисы Google',
  ),
  SplitTunnelPreset(
    domain: 'tiktok.com',
    label: 'TikTok',
    subtitle: 'Короткие видео',
  ),
  SplitTunnelPreset(
    domain: 'instagram.com',
    label: 'Instagram',
    subtitle: 'Instagram, Facebook',
  ),
  SplitTunnelPreset(
    domain: 'whatsapp.com',
    label: 'WhatsApp',
    subtitle: 'Звонки и сообщения',
  ),
  SplitTunnelPreset(
    domain: 'telegram.org',
    label: 'Telegram',
    subtitle: 'Каналы, звонки, медиа',
  ),
  SplitTunnelPreset(
    domain: 'discord.com',
    label: 'Discord',
    subtitle: 'Голос и сообщества',
  ),
  SplitTunnelPreset(
    domain: 'chatgpt.com',
    label: 'ChatGPT',
    subtitle: 'Нейросеть',
  ),
  SplitTunnelPreset(
    domain: 'claude.ai',
    label: 'Claude',
    subtitle: 'Нейросеть',
  ),
  SplitTunnelPreset(
    domain: 'gemini.google.com',
    label: 'Gemini',
    subtitle: 'Нейросеть',
  ),
];

/// Extra suffixes applied when the primary preset domain is enabled.
const kSplitTunnelDomainAliases = <String, List<String>>{
  'youtube.com': [
    'youtu.be',
    'googlevideo.com',
    'ytimg.com',
    'ggpht.com',
    'googleapis.com',
    'gvt1.com',
  ],
  'tiktok.com': [
    'tiktokv.com',
    'tiktokcdn.com',
    'musical.ly',
    'byteoversea.com',
  ],
  'instagram.com': [
    'cdninstagram.com',
    'instagram.net',
    'facebook.com',
    'fb.com',
    'fbcdn.net',
    'messenger.com',
  ],
  'cloudflare.com': [
    'cloudflare-dns.com',
  ],
  'whatsapp.com': [
    'wa.me',
    'whatsapp.net',
    'cdn.whatsapp.net',
  ],
  'telegram.org': [
    't.me',
    'tx.me',
    'telegram.me',
    'telegram.dog',
    'telegram.space',
    'tdesktop.com',
    'telegra.ph',
    'telesco.pe',
    'api.telegram.org',
    'core.telegram.org',
    'desktop.telegram.org',
    'telegram-cdn.org',
    'cdn-telegram.org',
  ],
  'discord.com': [
    'discord.gg',
    'discordapp.com',
    'discord.media',
    'discordcdn.com',
  ],
  'chatgpt.com': [
    'openai.com',
    'chat.openai.com',
    'oaiusercontent.com',
  ],
  'claude.ai': [
    'anthropic.com',
  ],
  'gemini.google.com': [
    // Web / app surfaces
    'aistudio.google.com',
    'notebooklm.google.com',
    'deepmind.google',
    'bard.google.com',
    // API / RPC
    'generativelanguage.googleapis.com',
    'alkalimakersuite-pa.clients6.google.com',
    'clients6.google.com',
    'googleapis.com',
    // Static / media / auth — Gemini breaks without these (SNIFF miss → direct).
    'google.com',
    'gstatic.com',
    'googleusercontent.com',
    'ggpht.com',
    'accounts.google.com',
    'withgoogle.com',
  ],
};

/// IP CIDRs routed to proxy when the matching preset is enabled (sites mode).
///
/// Telegram clients often skip SNI/DNS and dial DC IPs — domain_suffix alone
/// leaves them on `final=direct`.
const kSplitTunnelProxyIpCidrs = <String, List<String>>{
  'telegram.org': [
    '91.108.4.0/22',
    '91.108.8.0/22',
    '91.108.12.0/22',
    '91.108.16.0/22',
    '91.108.20.0/22',
    '91.108.56.0/22',
    '149.154.160.0/20',
    '185.76.151.0/24',
  ],
};
