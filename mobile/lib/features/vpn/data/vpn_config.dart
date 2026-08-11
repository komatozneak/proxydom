import 'vless_link_parser.dart';

/// Native VPN core selected by `/vpn/config` (ADR 006 ``active_core``).
enum VpnActiveCore {
  xray,
  trusttunnel,
}

/// Immutable models for `GET /api/v1/vpn/config` (Xray XOR TrustTunnel).
class VpnConfig {
  const VpnConfig({
    required this.username,
    required this.links,
    required this.expire,
    required this.activeCore,
    this.xrayProfile,
    this.trusttunnelProfile,
    this.nodeHost,
  });

  final String username;
  final List<String> links;
  final DateTime expire;

  /// Authoritative core for this connect session.
  final VpnActiveCore activeCore;

  /// Native-runtime Xray profile (schema 1|2). Required when [activeCore] is xray.
  final XrayProfile? xrayProfile;

  /// TrustTunnel core profile. Required when [activeCore] is trusttunnel.
  final TrustTunnelProfile? trusttunnelProfile;

  /// Egress VPS host from `GET /vpn/config` (`node_host`).
  final String? nodeHost;

  bool get isTrustTunnelSession => activeCore == VpnActiveCore.trusttunnel;

  /// Expected public egress IP/host for E2E checks.
  String? get expectedEgressHost {
    final host = nodeHost?.trim();
    if (host != null && host.isNotEmpty) return host;
    final tt = trusttunnelProfile;
    if (tt != null) {
      final hostname = tt.hostname.trim();
      if (hostname.isNotEmpty) return hostname;
      if (tt.addresses.isNotEmpty) {
        final addr = tt.addresses.first.split(':').first.trim();
        if (addr.isNotEmpty) return addr;
      }
    }
    final candidates = xrayProfile?.candidates ?? const <XrayCandidate>[];
    if (candidates.isEmpty) return null;
    final candidateHost = candidates.first.host.trim();
    if (candidateHost.isNotEmpty && candidateHost != 'unknown') {
      return candidateHost;
    }
    return null;
  }

  /// Ordered unique egress hosts for TUN bypass / direct cidr.
  List<String> get egressHosts {
    if (isTrustTunnelSession) {
      final host = expectedEgressHost;
      return host == null ? const [] : [host];
    }
    return [
      for (final candidate in xrayProfile?.candidates ?? const <XrayCandidate>[])
        if (candidate.host.isNotEmpty && candidate.host != 'unknown')
          candidate.host,
    ];
  }

  /// Preferred hop: match [nodeHost], else first candidate.
  ///
  /// Only valid for Xray sessions — callers must not use this for TT.
  XrayCandidate get primaryCandidate {
    final profile = xrayProfile;
    if (profile == null || profile.candidates.isEmpty) {
      throw StateError('primaryCandidate requires an Xray profile');
    }
    final host = nodeHost?.trim();
    if (host != null && host.isNotEmpty) {
      for (final candidate in profile.candidates) {
        if (candidate.host == host) return candidate;
      }
    }
    return profile.candidates.first;
  }

  /// Copy with a single primary candidate (nest connect path).
  VpnConfig withPrimaryCandidateOnly() {
    if (isTrustTunnelSession) return this;
    final primary = primaryCandidate;
    return VpnConfig(
      username: username,
      links: links,
      expire: expire,
      activeCore: VpnActiveCore.xray,
      xrayProfile: XrayProfile(
        schemaVersion: xrayProfile!.schemaVersion,
        candidates: [primary],
      ),
      trusttunnelProfile: trusttunnelProfile,
      nodeHost: nodeHost ?? primary.host,
    );
  }

  factory VpnConfig.fromJson(Map<String, dynamic> json) {
    final links = (json['links'] as List? ?? const []).cast<String>();
    final rawTt = json['trusttunnel_profile'];
    final TrustTunnelProfile? tt = rawTt is Map
        ? TrustTunnelProfile.fromJson(Map<String, dynamic>.from(rawTt))
        : null;
    final rawCore = (json['active_core'] as String?)?.trim().toLowerCase();
    final hasXrayMap = json['xray_profile'] is Map;

    final VpnActiveCore activeCore;
    if (rawCore == 'trusttunnel') {
      activeCore = VpnActiveCore.trusttunnel;
    } else if (rawCore == 'xray') {
      activeCore = VpnActiveCore.xray;
    } else if (tt != null && !hasXrayMap) {
      // Legacy payload without active_core: TT-only body.
      activeCore = VpnActiveCore.trusttunnel;
    } else {
      activeCore = VpnActiveCore.xray;
    }

    if (activeCore == VpnActiveCore.trusttunnel) {
      if (tt == null) {
        throw const FormatException(
          'active_core=trusttunnel requires trusttunnel_profile',
        );
      }
      final nodeHost = json['node_host'] as String?;
      return VpnConfig(
        username: json['username'] as String,
        links: links,
        expire: DateTime.fromMillisecondsSinceEpoch(
          (json['expire'] as int) * 1000,
          isUtc: true,
        ),
        activeCore: VpnActiveCore.trusttunnel,
        xrayProfile: null,
        trusttunnelProfile: tt,
        nodeHost: (nodeHost != null && nodeHost.isNotEmpty)
            ? nodeHost
            : tt.hostname,
      );
    }

    final xrayProfile = _resolveXrayProfile(json, links: links);
    final nodeHost = json['node_host'] as String?;
    return VpnConfig(
      username: json['username'] as String,
      links: links,
      expire: DateTime.fromMillisecondsSinceEpoch(
        (json['expire'] as int) * 1000,
        isUtc: true,
      ),
      activeCore: VpnActiveCore.xray,
      xrayProfile: xrayProfile,
      trusttunnelProfile: tt,
      nodeHost: nodeHost?.isNotEmpty == true
          ? nodeHost
          : xrayProfile.candidates.first.host,
    );
  }

  Map<String, dynamic> toJson() => {
        'username': username,
        'links': links,
        'expire': expire.millisecondsSinceEpoch ~/ 1000,
        'active_core':
            activeCore == VpnActiveCore.trusttunnel ? 'trusttunnel' : 'xray',
        if (xrayProfile != null) 'xray_profile': xrayProfile!.toJson(),
        if (trusttunnelProfile != null)
          'trusttunnel_profile': trusttunnelProfile!.toJson(),
        if (nodeHost != null) 'node_host': nodeHost,
      };

  static XrayProfile _resolveXrayProfile(
    Map<String, dynamic> json, {
    required List<String> links,
  }) {
    final rawProfile = json['xray_profile'];
    if (rawProfile is Map) {
      return XrayProfile.fromJson(Map<String, dynamic>.from(rawProfile));
    }

    final vless = pickVlessLink(
      selectedLink: json['selected_link'] as String?,
      links: links,
    );
    if (vless == null) {
      throw const FormatException(
        'vpn/config missing xray_profile and no vless:// link for fallback',
      );
    }
    final fallback = _realityFallbackFromSingBox(json['sing_box_config']);
    final candidate = xrayCandidateFromVlessLink(
      vless,
      realityFallback: fallback,
    );
    return XrayProfile(schemaVersion: 1, candidates: [candidate]);
  }

  /// Fill blank Reality fields from legacy sing-box outbound when present.
  static RealityFallback? _realityFallbackFromSingBox(dynamic raw) {
    if (raw is! Map) return null;
    final outbounds = raw['outbounds'];
    if (outbounds is! List) return null;
    for (final entry in outbounds) {
      if (entry is! Map) continue;
      final tls = entry['tls'];
      if (tls is! Map) continue;
      final reality = tls['reality'];
      if (reality is! Map) continue;
      return RealityFallback(
        publicKey: reality['public_key'] as String?,
        shortId: reality['short_id'] as String?,
        serverName: tls['server_name'] as String?,
      );
    }
    return null;
  }
}

/// Backend `xray_profile` (schema 1|2).
class XrayProfile {
  const XrayProfile({
    required this.schemaVersion,
    required this.candidates,
  });

  final int schemaVersion;
  final List<XrayCandidate> candidates;

  factory XrayProfile.fromJson(Map<String, dynamic> json) {
    final schemaVersion = json['schema_version'] as int;
    if (schemaVersion != 1 && schemaVersion != 2) {
      throw FormatException(
        'Unsupported xray_profile schema_version: $schemaVersion',
      );
    }
    final rawCandidates = json['candidates'] as List;
    final candidates = rawCandidates
        .map(
          (candidate) => XrayCandidate.fromJson(
            Map<String, dynamic>.from(candidate as Map),
          ),
        )
        .toList(growable: false);
    if (candidates.isEmpty) {
      throw const FormatException('xray_profile candidates must not be empty');
    }
    return XrayProfile(
      schemaVersion: schemaVersion,
      candidates: candidates,
    );
  }

  Map<String, dynamic> toJson() => {
        'schema_version': schemaVersion,
        'candidates':
            candidates.map((candidate) => candidate.toJson()).toList(),
      };
}

/// Complete credentials and transport settings for one Xray egress.
class XrayCandidate {
  const XrayCandidate({
    required this.id,
    required this.label,
    required this.host,
    required this.port,
    required this.protocol,
    required this.uuid,
    required this.flow,
    required this.transport,
    required this.security,
    required this.serverName,
    required this.publicKey,
    required this.shortId,
    required this.fingerprint,
    required this.spiderX,
    this.region,
    this.purpose,
    this.path,
    this.mode,
  });

  final String id;
  final String label;
  final String host;
  final int port;
  final String protocol;
  final String uuid;
  final String? flow;
  final String transport;
  final String security;
  final String serverName;
  final String publicKey;
  final String shortId;
  final String fingerprint;
  final String spiderX;
  final String? region;
  final String? purpose;
  final String? path;
  final String? mode;

  factory XrayCandidate.fromJson(Map<String, dynamic> json) {
    final protocol = json['protocol'] as String? ?? '';
    if (protocol != 'vless') {
      throw FormatException('Unsupported Xray protocol: $protocol');
    }
    final security = json['security'] as String? ?? '';
    if (security != 'reality') {
      throw FormatException('Unsupported Xray security: $security');
    }
    final port = _asInt(json['port']);
    if (port < 1 || port > 65535) {
      throw FormatException('Invalid Xray candidate port: $port');
    }
    final publicKey = (json['public_key'] as String? ?? '').trim();
    final serverName = (json['server_name'] as String? ?? '').trim();
    final shortId = (json['short_id'] as String? ?? '').trim();
    final fingerprint = (json['fingerprint'] as String? ?? '').trim();
    if (publicKey.isEmpty ||
        serverName.isEmpty ||
        shortId.isEmpty ||
        fingerprint.isEmpty) {
      throw const FormatException(
        'Xray candidate missing Reality fields '
        '(public_key/server_name/short_id/fingerprint)',
      );
    }
    final host = json['host'] as String? ?? '';
    final path = (json['path'] as String?)?.trim();
    final mode = (json['mode'] as String?)?.trim();
    return XrayCandidate(
      id: json['id'] as String? ?? host,
      label: json['label'] as String? ?? host,
      host: host,
      port: port,
      protocol: protocol,
      uuid: json['uuid'] as String? ?? '',
      flow: json['flow'] as String?,
      transport: json['transport'] as String? ?? 'tcp',
      security: security,
      serverName: serverName,
      publicKey: publicKey,
      shortId: shortId,
      fingerprint: fingerprint,
      spiderX: json['spider_x'] as String? ?? '/',
      region: (json['region'] as String?)?.trim(),
      purpose: (json['purpose'] as String?)?.trim(),
      path: (path == null || path.isEmpty) ? null : path,
      mode: (mode == null || mode.isEmpty) ? null : mode,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'host': host,
        'port': port,
        'protocol': protocol,
        'uuid': uuid,
        'flow': flow,
        'transport': transport,
        'security': security,
        'server_name': serverName,
        'public_key': publicKey,
        'short_id': shortId,
        'fingerprint': fingerprint,
        'spider_x': spiderX,
        if (region != null) 'region': region,
        if (purpose != null) 'purpose': purpose,
        if (path != null) 'path': path,
        if (mode != null) 'mode': mode,
      };
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed != null) return parsed;
  }
  throw FormatException('Expected int, got: $value');
}

/// TrustTunnel client profile (ADR 006). Defaults prefer http2.
class TrustTunnelProfile {
  const TrustTunnelProfile({
    required this.schemaVersion,
    required this.nodeId,
    required this.hostname,
    required this.addresses,
    required this.region,
    required this.purpose,
    required this.username,
    required this.password,
    required this.upstreamProtocol,
    required this.upstreamFallbackProtocol,
    required this.antiDpi,
    required this.dnsUpstreams,
    required this.toml,
  });

  final int schemaVersion;
  final String nodeId;
  final String hostname;
  final List<String> addresses;
  final String? region;
  final String? purpose;
  final String username;
  final String password;
  final String upstreamProtocol;
  final String upstreamFallbackProtocol;
  final bool antiDpi;
  final List<String> dnsUpstreams;
  final String toml;

  factory TrustTunnelProfile.fromJson(Map<String, dynamic> json) {
    final schemaVersion = json['schema_version'] as int;
    if (schemaVersion != 1) {
      throw FormatException(
        'Unsupported trusttunnel_profile schema_version: $schemaVersion',
      );
    }
    final toml = json['toml'] as String? ?? '';
    final hostname = json['hostname'] as String? ?? '';
    final username = json['username'] as String? ?? '';
    final password = json['password'] as String? ?? '';
    if (toml.isEmpty ||
        hostname.isEmpty ||
        username.isEmpty ||
        password.isEmpty) {
      throw const FormatException('Incomplete trusttunnel_profile');
    }
    return TrustTunnelProfile(
      schemaVersion: schemaVersion,
      nodeId: json['node_id'] as String? ?? '',
      hostname: hostname,
      addresses: (json['addresses'] as List? ?? const []).cast<String>(),
      region: json['region'] as String?,
      purpose: json['purpose'] as String?,
      username: username,
      password: password,
      upstreamProtocol: json['upstream_protocol'] as String? ?? 'http2',
      upstreamFallbackProtocol:
          json['upstream_fallback_protocol'] as String? ?? 'http2',
      antiDpi: json['anti_dpi'] as bool? ?? false,
      dnsUpstreams: (json['dns_upstreams'] as List? ?? const []).cast<String>(),
      toml: toml,
    );
  }

  Map<String, dynamic> toJson() => {
        'schema_version': schemaVersion,
        'node_id': nodeId,
        'hostname': hostname,
        'addresses': addresses,
        if (region != null) 'region': region,
        if (purpose != null) 'purpose': purpose,
        'username': username,
        'password': password,
        'upstream_protocol': upstreamProtocol,
        'upstream_fallback_protocol': upstreamFallbackProtocol,
        'anti_dpi': antiDpi,
        'dns_upstreams': dnsUpstreams,
        'toml': toml,
      };
}

/// In-memory cache of the last fetched config. Singleton.
class VpnConfigCache {
  VpnConfigCache._();
  static final VpnConfigCache instance = VpnConfigCache._();

  VpnConfig? _current;
  VpnConfig? get current => _current;

  void set(VpnConfig config) {
    _current = config;
  }

  void clear() {
    _current = null;
  }
}
