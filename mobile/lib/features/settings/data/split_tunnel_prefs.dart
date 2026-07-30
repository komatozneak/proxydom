import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// One custom site that should use `direct` when enabled.
class SplitTunnelSite {
  const SplitTunnelSite({
    required this.id,
    required this.domain,
    required this.enabled,
    this.label = '',
  });

  final String id;
  final String domain;
  final bool enabled;
  final String label;

  SplitTunnelSite copyWith({
    String? id,
    String? domain,
    bool? enabled,
    String? label,
  }) {
    return SplitTunnelSite(
      id: id ?? this.id,
      domain: domain ?? this.domain,
      enabled: enabled ?? this.enabled,
      label: label ?? this.label,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'domain': domain,
        'enabled': enabled,
        'label': label,
      };

  factory SplitTunnelSite.fromJson(Map<String, dynamic> json) {
    return SplitTunnelSite(
      id: '${json['id'] ?? ''}',
      domain: '${json['domain'] ?? ''}',
      enabled: json['enabled'] as bool? ?? true,
      label: '${json['label'] ?? ''}',
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

  /// Enabled custom domains for sing-box `domain_suffix` rules.
  static Future<List<String>> enabledDomainSuffixes() async {
    final sites = await loadSites();
    return sites.where((s) => s.enabled).map((s) => s.domain).toList();
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

  static Future<void> _bumpDraft(SharedPreferences prefs) async {
    final draft = (prefs.getInt(_draftRevKey) ?? 0) + 1;
    await prefs.setInt(_draftRevKey, draft);
  }
}
