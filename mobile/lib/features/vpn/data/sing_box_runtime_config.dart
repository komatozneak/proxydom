import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/config.dart';
import 'vpn_config.dart';
import 'vpn_service_config.dart';

/// FakeIP range kept for docs/tests — not used in Android runtime (P0 egress).
const fakeIpV4Range = '198.18.0.0/15';

/// Собирает sing-box JSON для libbox 1.13+ на Android (TUN fd уже создан VpnService).
///
/// ## Why this shape (Pixel verified 2026-07-14)
/// - **No FakeIP** — FakeIP + vision left the system “connected” with no egress.
/// - **No remote rule-sets from GitHub** — RF block of GitHub (2026-07-14) breaks
///   `download_detour: direct` on connect; use [localRulePaths] from APK assets.
/// - **UDP DNS via proxy** — DoH/FakeIP were hanging when egress was sick.
/// - Split-tunnel RU via **local** `.srs` only (VK/Yandex → direct).
String buildRuntimeSingBoxJson({
  required VpnConfig config,
  required VpnServiceConfig service,
  Map<String, String> localRulePaths = const {},
}) {
  final outbound = config.singBoxConfig.primaryOutbound!;
  final proxyTag = outbound.tag.isNotEmpty ? outbound.tag : 'proxy';
  final serverHost = outbound.server;

  final outboundJson = outbound.toJson();
  outboundJson.putIfAbsent('network', () => 'tcp');

  final directCidrs = <String>{
    if (_ipv4Cidr(serverHost) != null) _ipv4Cidr(serverHost)!,
    ...service.controlPlaneHosts.map(_ipv4Cidr).whereType<String>(),
  };
  try {
    final apiHost = Uri.parse(AppConfig.baseUrl).host;
    final apiCidr = _ipv4Cidr(apiHost);
    if (apiCidr != null) directCidrs.add(apiCidr);
  } catch (_) {}

  final hasLocalRules = localRulePaths.isNotEmpty;

  final routeRules = <Map<String, dynamic>>[
    {
      'inbound': 'tun-in',
      'action': 'sniff',
    },
    {
      'port': <int>[53],
      'action': 'hijack-dns',
    },
    {
      'protocol': 'dns',
      'action': 'hijack-dns',
    },
    if (directCidrs.isNotEmpty)
      {
        'ip_cidr': directCidrs.toList(),
        'outbound': 'direct',
      },
    if (hasLocalRules) ...[
      {
        'rule_set': 'geosite-category-ru',
        'outbound': 'direct',
      },
      {
        'rule_set': 'geosite-tld-ru',
        'outbound': 'direct',
      },
      {
        'rule_set': 'geoip-ru',
        'outbound': 'direct',
      },
    ],
  ];

  final runtime = <String, dynamic>{
    'log': {'level': kDebugMode ? 'debug' : config.singBoxConfig.logLevel},
    'dns': {
      'servers': [
        {
          'type': 'udp',
          'tag': 'dns-remote',
          'server': '1.1.1.1',
          'server_port': 53,
          'detour': proxyTag,
        },
      ],
      'final': 'dns-remote',
      'strategy': 'ipv4_only',
      'independent_cache': true,
    },
    'inbounds': [
      {
        'type': 'tun',
        'tag': 'tun-in',
        'interface_name': 'tun0',
        'mtu': service.mtu,
        'address': ['${service.address}/${service.addressPrefix}'],
        'auto_route': false,
        'stack': 'system',
      },
    ],
    'outbounds': [
      {'type': 'direct', 'tag': 'direct'},
      outboundJson,
    ],
    'route': {
      'rules': routeRules,
      if (hasLocalRules)
        'rule_set': [
          for (final e in localRulePaths.entries)
            {
              'type': 'local',
              'tag': e.key,
              'format': 'binary',
              'path': e.value,
            },
        ],
      'final': proxyTag,
      'auto_detect_interface': true,
    },
  };

  return jsonEncode(runtime);
}

final _ipv4Host = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');

/// sing-box `ip_cidr` needs an address, not a DNS name (`hostname/32` is invalid).
String? _ipv4Cidr(String host) {
  if (host.isEmpty || host == 'unknown') return null;
  if (_ipv4Host.hasMatch(host)) return '$host/32';
  if (host == 'api.teremokconnect.online' ||
      host.endsWith('.teremokconnect.online')) {
    return '${AppConfig.vpsIpv4}/32';
  }
  return null;
}
