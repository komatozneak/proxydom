import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/features/settings/data/vpn_route_mode.dart';
import 'package:teremok_connect/features/vpn/data/sing_box_runtime_config.dart';
import 'package:teremok_connect/features/vpn/data/vpn_config.dart';
import 'package:teremok_connect/features/vpn/data/vpn_service_config.dart';

VpnConfig _cfg() => VpnConfig.fromJson({
      'username': 'test_user',
      'links': ['vless://abc@45.91.248.91:443?type=tcp#test_user'],
      'expire': 1785654092,
      'sing_box_config': {
        'log': {'level': 'info'},
        'inbounds': [
          {
            'type': 'tun',
            'address': ['172.19.0.1/30'],
            'auto_route': true,
          },
        ],
        'outbounds': [
          {
            'type': 'vless',
            'tag': 'proxy',
            'server': '45.91.248.91',
            'server_port': 443,
            'uuid': '12345678-1234-1234-1234-123456789012',
            'flow': 'xtls-rprx-vision',
            'tls': {
              'enabled': true,
              'server_name': 'www.cloudflare.com',
              'utls': {'enabled': true, 'fingerprint': 'chrome'},
              'reality': {
                'enabled': true,
                'public_key': 'pk',
                'short_id': 'abcd',
              },
            },
          },
        ],
      },
    });

Map<String, dynamic> _route(String json) =>
    (jsonDecode(json) as Map<String, dynamic>)['route'] as Map<String, dynamic>;

void main() {
  final localRules = {
    'geosite-category-ru': '/data/rules/geosite-category-ru.srs',
    'geosite-tld-ru': '/data/rules/geosite-tld-ru.srs',
    'geoip-ru': '/data/rules/geoip-ru.srs',
  };
  const sitesCustom = ['youtube.com', 'tiktok.com'];

  test('smart/full/sites allowlist: sites final=direct + selected→proxy', () {
    final service = VpnServiceConfig.fromVpnConfig(_cfg());

    final smart = buildRuntimeSingBoxJson(
      config: _cfg(),
      service: service,
      routeMode: VpnRouteMode.smart,
      localRulePaths: localRules,
      includeBundledRuRuleSets: true,
    );
    final full = buildRuntimeSingBoxJson(
      config: _cfg(),
      service: service,
      routeMode: VpnRouteMode.full,
      localRulePaths: localRules,
    );
    final sites = buildRuntimeSingBoxJson(
      config: _cfg(),
      service: service,
      routeMode: VpnRouteMode.sites,
      customProxyDomainSuffixes: sitesCustom,
    );
    final sitesEmpty = buildRuntimeSingBoxJson(
      config: _cfg(),
      service: service,
      routeMode: VpnRouteMode.sites,
      customProxyDomainSuffixes: const [],
    );

    final rSmart = _route(smart);
    final rFull = _route(full);
    final rSites = _route(sites);
    final rEmpty = _route(sitesEmpty);

    expect(rSmart['final'], 'proxy');
    expect(rSmart.containsKey('rule_set'), isTrue);
    expect(rFull['final'], 'proxy');
    expect(rFull.containsKey('rule_set'), isFalse);
    expect(rSites['final'], 'direct');
    expect(rEmpty['final'], 'proxy');

    // Multi-outbound urltest: final=proxy is the urltest group (failover selector).
    final smartOut = (jsonDecode(smart) as Map)['outbounds'] as List;
    final proxyGroup = smartOut.cast<Map>().firstWhere((o) => o['tag'] == 'proxy');
    expect(proxyGroup['type'], 'urltest');
    expect((proxyGroup['outbounds'] as List), isNotEmpty);

    final sitesRules = (rSites['rules'] as List).cast<Map<String, dynamic>>();
    final allow = sitesRules.firstWhere(
      (r) => r['outbound'] == 'proxy' && r['domain_suffix'] != null,
    );
    expect(
      (allow['domain_suffix'] as List).toSet(),
      sitesCustom.toSet(),
    );

    final dns = (jsonDecode(sites) as Map)['dns'] as Map;
    final servers = dns['servers'] as List;
    expect((servers[0] as Map).containsKey('detour'), isFalse);

    expect(smart, isNot(equals(full)));
    expect(full, isNot(equals(sites)));
    expect(smart, isNot(equals(sites)));
  });
}

/// Pixel acceptance (manual):
/// 1. ≥2 connected nodes → reconnect → urltest children ≥2, final=proxy.
/// 2. Stop preferred node → traffic/ping moves to another hop without changing location (≤~1m).
/// 3. Single node → one VLESS child + urltest final=proxy (same as today UX).
/// 4. smart/full/sites unchanged (sites final=direct, DNS no detour:direct).
