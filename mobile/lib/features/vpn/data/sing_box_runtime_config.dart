import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'vpn_config.dart';
import 'vpn_service_config.dart';

/// FakeIP range for sing-box 1.12+ DNS server type.
const fakeIpV4Range = '198.18.0.0/15';

/// Собирает sing-box JSON для libbox 1.13+ на Android (TUN fd уже создан VpnService).
///
/// sing-box 1.13 убрал legacy inbound fields (`sniff`, `sniff_override_destination`);
/// sniff/hijack-dns — только через route rules. DNS servers — формат 1.12+ (`type`+`server`).
String buildRuntimeSingBoxJson({
  required VpnConfig config,
  required VpnServiceConfig service,
}) {
  final outbound = config.singBoxConfig.primaryOutbound!;
  final proxyTag = outbound.tag.isNotEmpty ? outbound.tag : 'proxy';
  final serverHost = outbound.server;

  final outboundJson = outbound.toJson();
  outboundJson.putIfAbsent('network', () => 'tcp');

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
    {
      'ip_cidr': <String>[fakeIpV4Range],
      'outbound': proxyTag,
    },
    if (serverHost.isNotEmpty && serverHost != 'unknown')
      {
        'ip_cidr': <String>['$serverHost/32'],
        'outbound': 'direct',
      },
  ];

  final runtime = <String, dynamic>{
    'log': {'level': kDebugMode ? 'debug' : config.singBoxConfig.logLevel},
    'dns': {
      'servers': [
        {
          'type': 'https',
          'tag': 'dns-remote',
          'server': '1.1.1.1',
          'server_port': 443,
          'path': '/dns-query',
          'detour': proxyTag,
        },
        {
          'type': 'fakeip',
          'tag': 'dns-fakeip',
          'inet4_range': fakeIpV4Range,
        },
      ],
      'rules': [
        {
          'query_type': <String>['A', 'AAAA'],
          'server': 'dns-fakeip',
        },
      ],
      'final': 'dns-remote',
      'reverse_mapping': true,
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
      'final': proxyTag,
      'auto_detect_interface': true,
    },
  };

  return jsonEncode(runtime);
}
