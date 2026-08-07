import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/features/vpn/data/sing_box_runtime_config.dart';
import 'package:teremok_connect/features/vpn/data/vpn_config.dart';
import 'package:teremok_connect/features/vpn/data/vpn_config_constructor.dart';
import 'package:teremok_connect/features/vpn/data/vpn_route_policy.dart';
import 'package:teremok_connect/features/vpn/data/vpn_service_config.dart';
import 'package:teremok_connect/features/vpn/data/vpn_session_inputs.dart';
import 'package:teremok_connect/features/settings/data/vpn_route_mode.dart';

VpnConfig _sampleVpnConfig({
  String server = '204.11.2.216',
  List<Map<String, dynamic>>? egressCandidates,
}) {
  return VpnConfig.fromJson({
    'username': 'test_user',
    'links': ['vless://abc@$server:443?type=tcp#test_user'],
    'expire': 1785654092,
    if (egressCandidates != null) 'egress_candidates': egressCandidates,
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
          'server': server,
          'server_port': 443,
          'uuid': '12345678-1234-1234-1234-123456789012',
          'flow': 'xtls-rprx-vision',
          'tls': {
            'enabled': true,
            'server_name': 'www.microsoft.com',
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
}

VpnServiceConfig _sampleServiceConfig() {
  return VpnServiceConfig.fromVpnConfig(_sampleVpnConfig());
}

void main() {
  group('VpnConfigConstructor policy defaults', () {
    test('prod flags: ads OFF, geoip OFF', () {
      expect(kAdsBlockEnabled, isFalse);
      expect(kGeoipRuEnabled, isFalse);
    });

    test('smart: udp/443 reject, yt force before RU, no geoip/ads, final=proxy', () {
      final config = _sampleVpnConfig();
      final service = VpnServiceConfig.fromVpnConfig(config);
      final json = jsonDecode(
        VpnConfigConstructor.build(
          VpnSessionInputs.fromVpnConfig(
            config: config,
            service: service,
            route: RoutePolicy(
              mode: VpnRouteMode.smart,
              localRulePaths: {
                'geosite-category-ru': '/data/rules/geosite-category-ru.srs',
                'geosite-tld-ru': '/data/rules/geosite-tld-ru.srs',
                'geoip-ru': '/data/rules/geoip-ru.srs',
                'geosite-category-ads-all':
                    '/data/rules/geosite-category-ads-all.srs',
              },
            ),
          ),
        ),
      ) as Map<String, dynamic>;
      final route = json['route'] as Map<String, dynamic>;
      final rules = (route['rules'] as List).cast<Map<String, dynamic>>();
      expect(route['final'], 'proxy');
      expect(rules[3], {
        'network': 'udp',
        'port': 443,
        'action': 'reject',
      });
      final ytIdx = rules.indexWhere(
        (r) =>
            r['outbound'] == 'proxy' &&
            r['domain_suffix'] is List &&
            (r['domain_suffix'] as List).contains('youtube.com'),
      );
      final ruIdx = rules.indexWhere(
        (r) => r['rule_set'] == 'geosite-category-ru',
      );
      expect(ytIdx, greaterThanOrEqualTo(0));
      expect(ruIdx, greaterThan(ytIdx));
      expect(rules.any((r) => r['rule_set'] == 'geoip-ru'), isFalse);
      expect(
        rules.any(
          (r) =>
              r['action'] == 'reject' &&
              r['rule_set'] == 'geosite-category-ads-all',
        ),
        isFalse,
      );
      final outs = (json['outbounds'] as List).cast<Map<String, dynamic>>();
      final vless = outs.where((o) => o['type'] == 'vless').toList();
      expect(vless.first.containsKey('uuid'), isTrue);
      expect(vless.first['network'], 'tcp');
    });
  });

  group('buildRuntimeSingBoxJson', () {
    test('urltest tag proxy is final + VpnPingMonitor group (N=1 child)', () {
      final json = jsonDecode(
        buildRuntimeSingBoxJson(
          config: _sampleVpnConfig(),
          service: _sampleServiceConfig(),
        ),
      ) as Map<String, dynamic>;

      final outbounds = (json['outbounds'] as List).cast<Map<String, dynamic>>();
      final urltest = outbounds.firstWhere((o) => o['tag'] == 'proxy');
      expect(urltest['type'], 'urltest');
      expect(urltest['tolerance'], 150);
      expect(urltest['interval'], '1m');
      final children = (urltest['outbounds'] as List).cast<String>();
      expect(children, hasLength(1));
      expect(children.first, startsWith('proxy-'));
      final vless = outbounds.where((o) => o['type'] == 'vless').toList();
      expect(vless, hasLength(1));
      expect(vless.first['tag'], children.first);
      final route = json['route'] as Map<String, dynamic>;
      expect(route['final'], 'proxy');
    });

    test('2+ egress_candidates → N VLESS + urltest final=proxy', () {
      final config = _sampleVpnConfig(
        server: '10.0.0.1',
        egressCandidates: [
          {'id': 'local', 'host': '10.0.0.1', 'label': 'Local'},
          {'id': 'usa', 'host': '10.0.0.2', 'label': 'USA'},
        ],
      );
      final json = jsonDecode(
        buildRuntimeSingBoxJson(
          config: config,
          service: VpnServiceConfig.fromVpnConfig(config),
        ),
      ) as Map<String, dynamic>;

      final outbounds = (json['outbounds'] as List).cast<Map<String, dynamic>>();
      final urltest = outbounds.firstWhere((o) => o['tag'] == 'proxy');
      expect(urltest['type'], 'urltest');
      expect(urltest['outbounds'], ['proxy-local', 'proxy-usa']);
      final vless = outbounds.where((o) => o['type'] == 'vless').toList();
      expect(vless.map((o) => o['server']), ['10.0.0.1', '10.0.0.2']);
      final route = json['route'] as Map<String, dynamic>;
      expect(route['final'], 'proxy');
      final cidrRule = (route['rules'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((r) => r['outbound'] == 'direct' && r['ip_cidr'] != null);
      expect(cidrRule['ip_cidr'], containsAll(['10.0.0.1/32', '10.0.0.2/32']));
      expect(VpnServiceConfig.fromVpnConfig(config).toMap()['egressHosts'],
          ['10.0.0.1', '10.0.0.2']);
    });

    test('smart/full: DoH DNS through proxy (VLESS is TCP-only)', () {
      final json = jsonDecode(
        buildRuntimeSingBoxJson(
          config: _sampleVpnConfig(),
          service: _sampleServiceConfig(),
        ),
      ) as Map<String, dynamic>;

      final dns = json['dns'] as Map<String, dynamic>;
      expect(dns['strategy'], 'ipv4_only');
      expect(dns['final'], 'dns-remote');
      expect(dns.containsKey('reverse_mapping'), isFalse);

      final servers = dns['servers'] as List<dynamic>;
      expect(servers, hasLength(2));
      final hosts = servers.firstWhere((s) => (s as Map)['type'] == 'hosts') as Map;
      expect(hosts['predefined']['api.teremokconnect.online'], isNotEmpty);
      final remote = servers.firstWhere((s) => (s as Map)['type'] == 'https') as Map;
      expect(remote['server'], '1.1.1.1');
      expect(remote['detour'], 'proxy');
      expect(remote.containsKey('server_port'), isFalse);
      expect(dns['rules'], isNotEmpty);
    });

    test('tun inbound использует system stack', () {
      final json = jsonDecode(
        buildRuntimeSingBoxJson(
          config: _sampleVpnConfig(),
          service: _sampleServiceConfig(),
        ),
      ) as Map<String, dynamic>;

      final inbound = (json['inbounds'] as List).first as Map<String, dynamic>;
      expect(inbound['stack'], 'system');
      expect(inbound['auto_route'], isFalse);
      expect(inbound['tag'], 'tun-in');
    });

    test('without local rules: sniff + VPS direct; final=proxy', () {
      final json = jsonDecode(
        buildRuntimeSingBoxJson(
          config: _sampleVpnConfig(server: '204.11.2.216'),
          service: _sampleServiceConfig(),
        ),
      ) as Map<String, dynamic>;

      final route = json['route'] as Map<String, dynamic>;
      final rules = route['rules'] as List<dynamic>;
      expect(rules[0], {'inbound': 'tun-in', 'action': 'sniff'});
      expect(rules[3], {
        'network': 'udp',
        'port': 443,
        'action': 'reject',
      });
      final cidrRule = rules[4] as Map<String, dynamic>;
      expect(cidrRule['outbound'], 'direct');
      expect(cidrRule['ip_cidr'], contains('204.11.2.216/32'));
      expect(rules.length, 5);
      expect(route['final'], 'proxy');
      expect(route.containsKey('rule_set'), isFalse);
    });

    test('with local rules: no GitHub URLs, type=local paths', () {
      final json = jsonDecode(
        buildRuntimeSingBoxJson(
          config: _sampleVpnConfig(),
          service: _sampleServiceConfig(),
          localRulePaths: {
            'geosite-category-ru': '/data/rules/geosite-category-ru.srs',
            'geosite-tld-ru': '/data/rules/geosite-tld-ru.srs',
            'geoip-ru': '/data/rules/geoip-ru.srs',
          },
        ),
      ) as Map<String, dynamic>;

      final route = json['route'] as Map<String, dynamic>;
      final ruleSets = route['rule_set'] as List<dynamic>;
      expect(ruleSets, hasLength(2));
      expect(
        ruleSets.map((e) => (e as Map)['tag']),
        isNot(contains('geoip-ru')),
      );
      for (final raw in ruleSets) {
        final rs = raw as Map<String, dynamic>;
        expect(rs['type'], 'local');
        expect(rs['format'], 'binary');
        expect(rs['path'], isNot(contains('github')));
        expect(rs['path'], endsWith('.srs'));
      }
      final encoded = jsonEncode(json);
      expect(encoded.contains('raw.githubusercontent.com'), isFalse);
      expect(encoded.contains('download_detour'), isFalse);
    });

    test('final outbound — proxy tag из config', () {
      final json = jsonDecode(
        buildRuntimeSingBoxJson(
          config: _sampleVpnConfig(),
          service: _sampleServiceConfig(),
        ),
      ) as Map<String, dynamic>;

      final route = json['route'] as Map<String, dynamic>;
      expect(route['final'], 'proxy');
      expect(route['auto_detect_interface'], isTrue);
    });

    test('full mode: no RU rules, final=proxy', () {
      final json = jsonDecode(
        buildRuntimeSingBoxJson(
          config: _sampleVpnConfig(),
          service: _sampleServiceConfig(),
          routeMode: VpnRouteMode.full,
          localRulePaths: {
            'geosite-category-ru': '/data/rules/geosite-category-ru.srs',
          },
          customDirectDomainSuffixes: ['example.com'],
        ),
      ) as Map<String, dynamic>;
      final route = json['route'] as Map<String, dynamic>;
      expect(route['final'], 'proxy');
      expect(route.containsKey('rule_set'), isFalse);
      final rules = route['rules'] as List<dynamic>;
      expect(
        rules.any((r) => (r as Map)['domain_suffix'] != null),
        isFalse,
      );
    });

    test('sites mode: selected → proxy; final=direct; DNS without detour=direct', () {
      final json = jsonDecode(
        buildRuntimeSingBoxJson(
          config: _sampleVpnConfig(),
          service: _sampleServiceConfig(),
          routeMode: VpnRouteMode.sites,
          customProxyDomainSuffixes: ['youtube.com', 'tiktok.com'],
        ),
      ) as Map<String, dynamic>;
      final route = json['route'] as Map<String, dynamic>;
      expect(route['final'], 'direct');
      final dns = json['dns'] as Map<String, dynamic>;
      final servers = dns['servers'] as List<dynamic>;
      // libbox rejects detour:direct — omit detour for underlying DNS.
      final remote = servers.firstWhere(
        (s) => (s as Map)['type'] == 'https' || (s as Map)['type'] == 'udp',
      ) as Map;
      expect(remote.containsKey('detour'), isFalse);
      final rules = route['rules'] as List<dynamic>;
      final proxyRule = rules.cast<Map<String, dynamic>>().firstWhere(
            (r) => r['outbound'] == 'proxy' && r['domain_suffix'] != null,
          );
      expect(proxyRule['domain_suffix'], ['tiktok.com', 'youtube.com']);
      expect(
        rules.any((r) =>
            (r as Map)['outbound'] == 'direct' && r['domain_suffix'] != null),
        isFalse,
      );
    });

    test('sites + Telegram: DC ip_cidr → proxy (apps dial IPs, not domains)', () {
      final json = jsonDecode(
        buildRuntimeSingBoxJson(
          config: _sampleVpnConfig(),
          service: _sampleServiceConfig(),
          routeMode: VpnRouteMode.sites,
          customProxyDomainSuffixes: ['telegram.org', 't.me'],
          customProxyIpCidrs: [
            '149.154.160.0/20',
            '91.108.4.0/22',
          ],
        ),
      ) as Map<String, dynamic>;
      final route = json['route'] as Map<String, dynamic>;
      expect(route['final'], 'direct');
      final rules = (route['rules'] as List).cast<Map<String, dynamic>>();
      final ipProxy = rules.firstWhere(
        (r) =>
            r['outbound'] == 'proxy' &&
            r['ip_cidr'] != null &&
            (r['ip_cidr'] as List).any((c) => '$c'.startsWith('149.154')),
      );
      expect(
        ipProxy['ip_cidr'],
        containsAll(['149.154.160.0/20', '91.108.4.0/22']),
      );
    });

    test('sites mode empty list: fallback final=proxy (Android-safe)', () {
      final json = jsonDecode(
        buildRuntimeSingBoxJson(
          config: _sampleVpnConfig(),
          service: _sampleServiceConfig(),
          routeMode: VpnRouteMode.sites,
          customProxyDomainSuffixes: const [],
        ),
      ) as Map<String, dynamic>;
      final route = json['route'] as Map<String, dynamic>;
      expect(route['final'], 'proxy');
      final dns = json['dns'] as Map<String, dynamic>;
      final servers = dns['servers'] as List<dynamic>;
      final remote = servers.firstWhere(
        (s) => (s as Map)['type'] == 'https' || (s as Map)['type'] == 'udp',
      ) as Map;
      expect(remote['detour'], 'proxy');
    });

    test('smart + RU: YouTube force-proxy before geosite-ru; no geoip-ru', () {
      final json = jsonDecode(
        buildRuntimeSingBoxJson(
          config: _sampleVpnConfig(),
          service: _sampleServiceConfig(),
          routeMode: VpnRouteMode.smart,
          includeAdsBlock: false,
          localRulePaths: {
            'geosite-category-ru': '/data/rules/geosite-category-ru.srs',
            'geosite-tld-ru': '/data/rules/geosite-tld-ru.srs',
            'geoip-ru': '/data/rules/geoip-ru.srs',
          },
        ),
      ) as Map<String, dynamic>;
      final route = json['route'] as Map<String, dynamic>;
      final rules = route['rules'] as List;
      final ruleSets = (route['rule_set'] as List).cast<Map<String, dynamic>>();
      final ytIdx = rules.indexWhere(
        (r) =>
            (r as Map)['outbound'] == 'proxy' &&
            r['domain_suffix'] is List &&
            (r['domain_suffix'] as List).contains('youtube.com'),
      );
      final geositeIdx = rules.indexWhere(
        (r) => (r as Map)['rule_set'] == 'geosite-category-ru',
      );
      expect(ytIdx, greaterThanOrEqualTo(0));
      expect(geositeIdx, greaterThan(ytIdx));
      expect(rules.any((r) => (r as Map)['rule_set'] == 'geoip-ru'), isFalse);
      expect(ruleSets.map((r) => r['tag']), isNot(contains('geoip-ru')));
      expect(ruleSets.map((r) => r['tag']), contains('geosite-category-ru'));
    });

    test('smart mode: custom → direct, final=proxy', () {
      final json = jsonDecode(
        buildRuntimeSingBoxJson(
          config: _sampleVpnConfig(),
          service: _sampleServiceConfig(),
          routeMode: VpnRouteMode.smart,
          customDirectDomainSuffixes: ['ozon.ru'],
        ),
      ) as Map<String, dynamic>;
      final route = json['route'] as Map<String, dynamic>;
      expect(route['final'], 'proxy');
      final rules = route['rules'] as List<dynamic>;
      final directRule = rules.cast<Map<String, dynamic>>().firstWhere(
            (r) => r['outbound'] == 'direct' && r['domain_suffix'] != null,
          );
      expect(directRule['domain_suffix'], ['ozon.ru']);
    });

    test('ads block ON: bypass YouTube before reject; reject after control-plane', () {
      final json = jsonDecode(
        buildRuntimeSingBoxJson(
          config: _sampleVpnConfig(server: '204.11.2.216'),
          service: _sampleServiceConfig(),
          includeAdsBlock: true,
          localRulePaths: {
            'geosite-category-ads-all': '/data/rules/geosite-category-ads-all.srs',
          },
        ),
      ) as Map<String, dynamic>;
      final route = json['route'] as Map<String, dynamic>;
      final ruleSets = (route['rule_set'] as List).cast<Map<String, dynamic>>();
      expect(
        ruleSets.any((rs) => rs['tag'] == 'geosite-category-ads-all'),
        isTrue,
      );

      final rules = (route['rules'] as List).cast<Map<String, dynamic>>();
      final cidrIdx = rules.indexWhere(
        (r) => r['outbound'] == 'direct' && r['ip_cidr'] != null,
      );
      final bypassIdx = rules.indexWhere(
        (r) =>
            r['outbound'] == 'proxy' &&
            r['domain_suffix'] is List &&
            (r['domain_suffix'] as List).contains('youtube.com'),
      );
      final adsIdx = rules.indexWhere(
        (r) => r['action'] == 'reject' && r['rule_set'] == 'geosite-category-ads-all',
      );
      expect(cidrIdx, greaterThanOrEqualTo(0));
      expect(bypassIdx, greaterThan(cidrIdx));
      expect(adsIdx, greaterThan(bypassIdx));
    });

    test('ads block OFF: no reject rule even with ads path', () {
      final json = jsonDecode(
        buildRuntimeSingBoxJson(
          config: _sampleVpnConfig(),
          service: _sampleServiceConfig(),
          includeAdsBlock: false,
          localRulePaths: {
            'geosite-category-ads-all': '/data/rules/geosite-category-ads-all.srs',
          },
        ),
      ) as Map<String, dynamic>;
      final route = json['route'] as Map<String, dynamic>;
      expect(route.containsKey('rule_set'), isFalse);
      final rules = (route['rules'] as List).cast<Map<String, dynamic>>();
      // QUIC reject stays; only rule_set-driven ads reject must be absent.
      expect(
        rules.any((r) => r['action'] == 'reject' && r.containsKey('rule_set')),
        isFalse,
      );
    });

    test('sites + ads: allowlist proxy before ads reject', () {
      final json = jsonDecode(
        buildRuntimeSingBoxJson(
          config: _sampleVpnConfig(),
          service: _sampleServiceConfig(),
          routeMode: VpnRouteMode.sites,
          includeAdsBlock: true,
          localRulePaths: {
            'geosite-category-ads-all': '/data/rules/geosite-category-ads-all.srs',
          },
          customProxyDomainSuffixes: ['youtube.com', 'tiktok.com'],
        ),
      ) as Map<String, dynamic>;
      final rules = (json['route'] as Map)['rules'] as List;
      final proxyIdx = rules.indexWhere(
        (r) =>
            (r as Map)['outbound'] == 'proxy' &&
            r['domain_suffix'] is List &&
            (r['domain_suffix'] as List).contains('tiktok.com'),
      );
      final adsIdx = rules.indexWhere(
        (r) =>
            (r as Map)['action'] == 'reject' &&
            r.containsKey('rule_set') &&
            r['rule_set'] == 'geosite-category-ads-all',
      );
      expect(proxyIdx, greaterThanOrEqualTo(0));
      expect(adsIdx, greaterThan(proxyIdx));
    });

    test('full mode + ads: reject present without RU', () {
      final json = jsonDecode(
        buildRuntimeSingBoxJson(
          config: _sampleVpnConfig(),
          service: _sampleServiceConfig(),
          routeMode: VpnRouteMode.full,
          includeAdsBlock: true,
          localRulePaths: {
            'geosite-category-ru': '/data/rules/geosite-category-ru.srs',
            'geosite-tld-ru': '/data/rules/geosite-tld-ru.srs',
            'geoip-ru': '/data/rules/geoip-ru.srs',
            'geosite-category-ads-all': '/data/rules/geosite-category-ads-all.srs',
          },
        ),
      ) as Map<String, dynamic>;
      final route = json['route'] as Map<String, dynamic>;
      final ruleSets = (route['rule_set'] as List).cast<Map<String, dynamic>>();
      expect(ruleSets, hasLength(1));
      expect(ruleSets.first['tag'], 'geosite-category-ads-all');
      final rules = (route['rules'] as List).cast<Map<String, dynamic>>();
      expect(
        rules.any(
          (r) =>
              r['action'] == 'reject' &&
              r['rule_set'] == 'geosite-category-ads-all',
        ),
        isTrue,
      );
      expect(
        rules.any((r) => r['rule_set'] == 'geosite-category-ru'),
        isFalse,
      );
    });

    test('quic: udp/443 → reject before domain rules (all modes)', () {
      for (final mode in VpnRouteMode.values) {
        final json = jsonDecode(
          buildRuntimeSingBoxJson(
            config: _sampleVpnConfig(),
            service: _sampleServiceConfig(),
            routeMode: mode,
          ),
        ) as Map<String, dynamic>;
        final rules = ((json['route'] as Map<String, dynamic>)['rules'] as List)
            .cast<Map<String, dynamic>>();
        final quicIdx = rules.indexWhere(
          (r) =>
              r['network'] == 'udp' &&
              r['port'] == 443 &&
              r['action'] == 'reject',
        );
        expect(quicIdx, greaterThanOrEqualTo(0), reason: 'mode=$mode');
        expect(
          rules.any(
            (r) =>
                r['network'] == 'udp' &&
                r['port'] == 443 &&
                r['outbound'] == 'direct',
          ),
          isFalse,
          reason: 'mode=$mode',
        );
        expect(quicIdx, lessThan(4), reason: 'mode=$mode early in pipeline');
        final firstDomainIdx = rules.indexWhere(
          (r) => r.containsKey('domain_suffix'),
        );
        if (firstDomainIdx >= 0) {
          expect(quicIdx, lessThan(firstDomainIdx), reason: 'mode=$mode');
        }
      }
    });
  });
}
