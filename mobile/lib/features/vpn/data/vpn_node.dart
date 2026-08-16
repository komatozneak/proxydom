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

  /// Core protocol: `vless-reality`, `trusttunnel`, or `hysteria2`.
  final String protocol;

  /// ISO region code (e.g. "us", "al", "uz") for YouTube/geo specialization.
  final String? region;

  /// Node role: `general`, `youtube`, `geo-us`, `geo-in`, `coming_soon`, … (ADR 006).
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

  /// Hysteria2 Free LTE path (ADR 015). In Free Auto via data-plane prove.
  bool get isHysteria => protocol == kVpnNodeProtocolHysteria2;

  /// YouTube-specialized egress (ad-free region or TrustTunnel YT node).
  bool get isYoutube => (purpose ?? '').toLowerCase() == 'youtube';

  /// Premium gaming TrustTunnel (EU / DE ping), never YouTube copy.
  bool get isGaming => (purpose ?? '').toLowerCase() == 'gaming';

  /// Placeholder for a not-yet-provisioned node — UI shows but disables it.
  bool get isComingSoon =>
      (purpose ?? '').toLowerCase() == 'coming_soon' ||
      status.toLowerCase() == 'coming_soon' ||
      locked;

  /// Geo-US services node (not YouTube — US shows mid-roll ads).
  bool get isGeoUs => (purpose ?? '').toLowerCase() == 'geo-us';

  /// Premium India geo exit (local apps / prices). Never Auto.
  bool get isGeoIn => (purpose ?? '').toLowerCase() == 'geo-in';

  /// Xray node eligible for Auto / General section (never TT / YT / coming-soon).
  bool get isGeneralXray =>
      !isTrustTunnel &&
      !isYoutube &&
      !isGaming &&
      !isComingSoon &&
      !isGeoUs &&
      !isGeoIn;

  /// True when this row may be tried in Auto for [isPremium].
  ///
  /// Free: metered Xray / Hy2. TT, YouTube, gaming, geo-in never.
  /// Retired EU Xray (`eu-primary`) never enters Auto.
  bool inAutoPool({required bool isPremium}) {
    if (host.isEmpty || host == '0.0.0.0') return false;
    if (isComingSoon) return false;
    if (isGeoIn) return false;
    if (!isConnected && !isDefault) return false;
    final idLower = id.trim().toLowerCase();
    if (idLower == 'eu-primary') return false;
    if (locked) return false;
    if (!isPremium) {
      if (isTrustTunnel || isYoutube || isGaming || requiresPremium) {
        return false;
      }
      return isHysteria ||
          protocol == kVpnNodeProtocolVlessReality ||
          isGeneralXray ||
          isGeoUs;
    }
    return true;
  }

  /// Legacy alias: Free-pool membership (tests / old call sites).
  bool get isAutoEligible => inAutoPool(isPremium: false);

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
const kVpnNodeProtocolHysteria2 = 'hysteria2';
