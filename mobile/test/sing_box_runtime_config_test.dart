import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/features/vpn/data/sing_box_runtime_config.dart';
import 'package:teremok_connect/features/vpn/data/vpn_config.dart';
import 'package:teremok_connect/features/vpn/data/vpn_service_config.dart';

VpnConfig _sampleVpnConfig({String server = '204.11.2.216'}) {
  return VpnConfig.fromJson({
    'username': 'test_user',
    'links': ['vless://abc@$server:443?type=tcp#test_user'],
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
  group('buildRuntimeSingBoxJson', () {
    test('использует UDP DNS через proxy (без FakeIP)', () {
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
      expect(servers, hasLength(1));
      expect(servers[0]['type'], 'udp');
      expect(servers[0]['server'], '1.1.1.1');
      expect(servers[0]['detour'], 'proxy');
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
        'ip_cidr': <String>['204.11.2.216/32'],
        'outbound': 'direct',
      });
      expect(rules.length, 4);
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
      expect(ruleSets, hasLength(3));
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
  });
}
