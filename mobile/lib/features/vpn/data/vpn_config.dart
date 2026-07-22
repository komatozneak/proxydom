/// Immutable-модели для ответа `GET /api/v1/vpn/config`.
///
/// Backend в DEV-режиме возвращает:
/// ```json
/// {
///   "username": "test_user_crypto",
///   "links": ["vless://..."],
///   "expire": 1785654092,
///   "sing_box_config": { ... }
/// }
/// ```
class VpnConfig {
  const VpnConfig({
    required this.username,
    required this.links,
    required this.expire,
    required this.singBoxConfig,
    this.nodeHost,
  });

  final String username;
  final List<String> links;
  final DateTime expire;
  final SingBoxConfig singBoxConfig;

  /// Egress VPS host from `GET /vpn/config` (`node_host`).
  final String? nodeHost;

  /// Expected public egress IP/host for E2E checks (falls back to outbound server).
  String? get expectedEgressHost {
    final host = nodeHost?.trim();
    if (host != null && host.isNotEmpty) return host;
    final server = singBoxConfig.primaryOutbound?.server.trim();
    if (server != null && server.isNotEmpty && server != 'unknown') {
      return server;
    }
    return null;
  }

  factory VpnConfig.fromJson(Map<String, dynamic> json) {
    final singBox = SingBoxConfig.fromJson(
      json['sing_box_config'] as Map<String, dynamic>,
    );
    final nodeHost = json['node_host'] as String?;
    return VpnConfig(
      username: json['username'] as String,
      links: (json['links'] as List).cast<String>(),
      expire: DateTime.fromMillisecondsSinceEpoch(
        (json['expire'] as int) * 1000,
        isUtc: true,
      ),
      singBoxConfig: singBox,
      nodeHost: nodeHost?.isNotEmpty == true
          ? nodeHost
          : singBox.primaryOutbound?.server,
    );
  }

  Map<String, dynamic> toJson() => {
    'username': username,
    'links': links,
    'expire': expire.millisecondsSinceEpoch ~/ 1000,
    'sing_box_config': singBoxConfig.toJson(),
    if (nodeHost != null) 'node_host': nodeHost,
  };
}

class SingBoxConfig {
  const SingBoxConfig({
    required this.logLevel,
    required this.inbounds,
    required this.outbounds,
  });

  final String logLevel;
  final List<SingBoxInbound> inbounds;
  final List<SingBoxOutbound> outbounds;

  factory SingBoxConfig.fromJson(Map<String, dynamic> json) {
    return SingBoxConfig(
      logLevel: (json['log']?['level'] as String?) ?? 'info',
      inbounds: ((json['inbounds'] as List?) ?? const [])
          .map((e) => SingBoxInbound.fromJson(e as Map<String, dynamic>))
          .toList(),
      outbounds: ((json['outbounds'] as List?) ?? const [])
          .map((e) => SingBoxOutbound.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'log': {'level': logLevel},
    'inbounds': inbounds.map((i) => i.toJson()).toList(),
    'outbounds': outbounds.map((o) => o.toJson()).toList(),
  };

  /// Первый outbound — то, что используется как proxy.
  SingBoxOutbound? get primaryOutbound =>
      outbounds.isEmpty ? null : outbounds.first;
}

class SingBoxInbound {
  const SingBoxInbound({
    required this.type,
    required this.inet4Address,
    this.inet6Address = '',
    required this.autoRoute,
    required this.strictRoute,
  });

  final String type;
  final String inet4Address;
  final String inet6Address;
  final bool autoRoute;
  final bool strictRoute;

  factory SingBoxInbound.fromJson(Map<String, dynamic> json) {
    return SingBoxInbound(
      type: json['type'] as String,
      inet4Address: (json['inet4_address'] as String?) ?? '172.19.0.1/30',
      inet6Address: (json['inet6_address'] as String?) ?? '',
      autoRoute: (json['auto_route'] as bool?) ?? true,
      strictRoute: (json['strict_route'] as bool?) ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    'inet4_address': inet4Address,
    if (inet6Address.isNotEmpty) 'inet6_address': inet6Address,
    'auto_route': autoRoute,
    'strict_route': strictRoute,
  };
}

class SingBoxOutbound {
  const SingBoxOutbound({
    required this.type,
    required this.tag,
    required this.server,
    required this.serverPort,
    required this.uuid,
    this.flow,
    this.tls,
  });

  final String type;
  final String tag;
  final String server;
  final int serverPort;
  final String uuid;
  final String? flow;
  final SingBoxTls? tls;

  factory SingBoxOutbound.fromJson(Map<String, dynamic> json) {
    return SingBoxOutbound(
      type: json['type'] as String,
      tag: (json['tag'] as String?) ?? 'proxy',
      server: json['server'] as String,
      serverPort: json['server_port'] as int,
      uuid: json['uuid'] as String,
      flow: json['flow'] as String?,
      tls: json['tls'] != null
          ? SingBoxTls.fromJson(json['tls'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    'tag': tag,
    'server': server,
    'server_port': serverPort,
    'uuid': uuid,
    if (flow != null) 'flow': flow,
    if (tls != null) 'tls': tls!.toJson(),
  };
}

class SingBoxTls {
  const SingBoxTls({
    required this.enabled,
    required this.serverName,
    required this.realityEnabled,
    required this.publicKey,
    required this.shortId,
    required this.fingerprint,
  });

  final bool enabled;
  final String serverName;
  final bool realityEnabled;
  final String publicKey;
  final String shortId;
  final String fingerprint;

  factory SingBoxTls.fromJson(Map<String, dynamic> json) {
    return SingBoxTls(
      enabled: (json['enabled'] as bool?) ?? false,
      serverName: (json['server_name'] as String?) ?? '',
      realityEnabled: (json['reality']?['enabled'] as bool?) ?? false,
      publicKey: (json['reality']?['public_key'] as String?) ?? '',
      shortId: (json['reality']?['short_id'] as String?) ?? '',
      fingerprint: (json['utls']?['fingerprint'] as String?) ?? 'chrome',
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'server_name': serverName,
    'utls': {'enabled': true, 'fingerprint': fingerprint},
    'reality': {
      'enabled': realityEnabled,
      'public_key': publicKey,
      'short_id': shortId,
    },
  };
}

/// In-memory кеш последнего полученного конфига. Singleton.
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