import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'vpn_config.dart';
import 'vpn_service_config.dart';

/// FakeIP range for sing-box 1.12+ DNS server type.
const fakeIpV4Range = '198.18.0.0/15';

/// Remote rule-set URLs (sing-box 1.12+; legacy `geosite:` / `geoip:` removed in 1.12).
/// There is no `geosite-ru.srs` upstream — use category-ru + tld-ru + geoip-ru.
/// Shipped copies: `assets/rules/*.srs` (offline / future local path).
const geositeCategoryRuUrl =
    'https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-category-ru.srs';
const geositeTldRuUrl =
    'https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-tld-ru.srs';
const geoipRuRuleSetUrl =
    'https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-ru.srs';

/// Собирает sing-box JSON для libbox 1.13+ на Android (TUN fd уже создан VpnService).
///
/// sing-box 1.13 убрал legacy inbound fields (`sniff`, `sniff_override_destination`);
/// sniff/hijack-dns — только через route rules. DNS servers — формат 1.12+ (`type`+`server`).
///
/// Split-tunnel: RU category / `.ru` TLD / geoip-ru → `direct` (VK/Yandex без VPN hop).
String buildRuntimeSingBoxJson({
  required VpnConfig config,
  required VpnServiceConfig service,
}) {
  final outbound = config.singBoxConfig.primaryOutbound!;
  final proxyTag = outbound.tag.isNotEmpty ? outbound.tag : 'proxy';
  final serverHost = outbound.server;

  final outboundJson = outbound.toJson();
  outboundJson.putIfAbsent('network', () => 'tcp');

  // RU direct BEFORE FakeIP→proxy so reverse_mapping can still match domains.
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
    if (serverHost.isNotEmpty && serverHost != 'unknown')
      {
        'ip_cidr': <String>['$serverHost/32'],
        'outbound': 'direct',
      },
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
    {
      'ip_cidr': <String>[fakeIpV4Range],
      'outbound': proxyTag,
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
      'rule_set': [
        {
          'tag': 'geosite-category-ru',
          'type': 'remote',
          'format': 'binary',
          'url': geositeCategoryRuUrl,
          'download_detour': 'direct',
        },
        {
          'tag': 'geosite-tld-ru',
          'type': 'remote',
          'format': 'binary',
          'url': geositeTldRuUrl,
          'download_detour': 'direct',
        },
        {
          'tag': 'geoip-ru',
          'type': 'remote',
          'format': 'binary',
          'url': geoipRuRuleSetUrl,
          'download_detour': 'direct',
        },
      ],
      'final': proxyTag,
      'auto_detect_interface': true,
    },
    // Required for remote rule-set caching on Android libbox.
    'experimental': {
      'cache_file': {
        'enabled': true,
        'store_rdrc': true,
      },
    },
  };

  return jsonEncode(runtime);
}
