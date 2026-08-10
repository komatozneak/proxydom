/// VPN egress node from `GET /api/v1/vpn/nodes`.
class VpnNode {
  const VpnNode({
    required this.id,
    required this.label,
    required this.host,
    required this.port,
    required this.status,
    required this.isDefault,
    this.name = '',
    this.protocol = kVpnNodeProtocolVlessReality,
    this.region,
    this.purpose,
    this.autoEligible,
    this.requiresPremium = false,
    this.locked = false,
    this.tier = 'free',
  });

  final String id;
  final String label;
  final String host;
  final int port;
  final String status;
  final bool isDefault;
  final String name;

  /// Core protocol: `vless-reality` (Xray) or `trusttunnel` (ADR 006).
  final String protocol;

  /// ISO region code (e.g. "us", "al", "uz") for YouTube/geo specialization.
  final String? region;

  /// Node role: `general`, `youtube`, `geo-us`, `coming_soon`, … (ADR 006).
  final String? purpose;

  /// Server hint: eligible for Auto picker. Null → derive via [isAutoEligible].
  final bool? autoEligible;

  /// Огонь-style: YouTube / premium nodes need Pro.
  final bool requiresPremium;

  /// UI lock (non-premium user or coming_soon).
  final bool locked;

  final String tier;

  bool get isConnected => status.toLowerCase() == 'connected';

  /// TrustTunnel node → client starts the TT core instead of Xray.
  bool get isTrustTunnel => protocol == kVpnNodeProtocolTrusttunnel;

  /// YouTube-specialized egress (ad-free region or TrustTunnel YT node).
  bool get isYoutube => (purpose ?? '').toLowerCase() == 'youtube';

  /// Placeholder for a not-yet-provisioned node — UI shows but disables it.
  bool get isComingSoon =>
      (purpose ?? '').toLowerCase() == 'coming_soon' ||
      status.toLowerCase() == 'coming_soon' ||
      locked;

  /// Geo-US services node (not YouTube — US shows mid-roll ads).
  bool get isGeoUs => (purpose ?? '').toLowerCase() == 'geo-us';

  /// Xray node eligible for Auto / General section (never TT / YT / coming-soon).
  bool get isGeneralXray =>
      !isTrustTunnel && !isYoutube && !isComingSoon && !isGeoUs;

  /// Auto picker gate — prefer server `auto_eligible`, else [isGeneralXray].
  bool get isAutoEligible =>
      autoEligible ?? (isGeneralXray && (isConnected || isDefault));

  factory VpnNode.fromJson(Map<String, dynamic> json) {
    final rawHost = (json['host'] as String?) ?? '';
    final host = _hostOnly(rawHost);
    return VpnNode(
      id: '${json['id'] ?? host}',
      label: (json['label'] as String?) ?? (json['name'] as String?) ?? '',
      host: host,
      port: (json['port'] as int?) ?? _portFromHost(rawHost) ?? 443,
      status: (json['status'] as String?) ?? 'unknown',
      isDefault: (json['is_default'] as bool?) ?? false,
      name: (json['name'] as String?) ?? '',
      protocol:
          (json['protocol'] as String?)?.trim() ?? kVpnNodeProtocolVlessReality,
      region: (json['region'] as String?)?.trim(),
      purpose: (json['purpose'] as String?)?.trim(),
      autoEligible: json['auto_eligible'] as bool?,
      requiresPremium: json['requires_premium'] as bool? ?? false,
      locked: json['locked'] as bool? ?? false,
      tier: (json['tier'] as String?)?.trim() ?? 'free',
    );
  }

  static String _hostOnly(String raw) {
    var h = raw.trim();
    if (h.startsWith('[')) {
      final end = h.indexOf(']');
      if (end > 0) return h.substring(1, end);
    }
    final colon = h.indexOf(':');
    if (colon > 0 && h.indexOf(':', colon + 1) < 0) {
      return h.substring(0, colon);
    }
    return h;
  }

  static int? _portFromHost(String raw) {
    final h = raw.trim();
    final colon = h.indexOf(':');
    if (colon <= 0 || h.indexOf(':', colon + 1) >= 0) return null;
    return int.tryParse(h.substring(colon + 1));
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'host': host,
        'port': port,
        'status': status,
        'is_default': isDefault,
        'name': name,
        'protocol': protocol,
        if (region != null) 'region': region,
        if (purpose != null) 'purpose': purpose,
        if (autoEligible != null) 'auto_eligible': autoEligible,
        'requires_premium': requiresPremium,
        'locked': locked,
        'tier': tier,
      };
}

/// Node protocol markers from `GET /api/v1/vpn/nodes` (ADR 006 dual-core).
const kVpnNodeProtocolVlessReality = 'vless-reality';
const kVpnNodeProtocolTrusttunnel = 'trusttunnel';
