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
    test('включает FakeIP DNS с reverse_mapping и dns.final', () {
      final json = jsonDecode(
        buildRuntimeSingBoxJson(
          config: _sampleVpnConfig(),
          service: _sampleServiceConfig(),
        ),
      ) as Map<String, dynamic>;

      final dns = json['dns'] as Map<String, dynamic>;
      expect(dns['reverse_mapping'], isTrue);
      expect(dns['strategy'], 'ipv4_only');
      expect(dns['final'], 'dns-remote');

      final servers = dns['servers'] as List<dynamic>;
      expect(servers, hasLength(2));
      expect(servers[0]['type'], 'https');
      expect(servers[0]['detour'], 'proxy');
      expect(servers[1]['type'], 'fakeip');
      expect(servers[1]['inet4_range'], fakeIpV4Range);
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

    test('route rules: sniff, hijack-dns, VPS+RU direct, then FakeIP→proxy', () {
      final json = jsonDecode(
        buildRuntimeSingBoxJson(
          config: _sampleVpnConfig(server: '204.11.2.216'),
          service: _sampleServiceConfig(),
        ),
      ) as Map<String, dynamic>;

      final rules = (json['route'] as Map)['rules'] as List<dynamic>;
      expect(rules[0], {'inbound': 'tun-in', 'action': 'sniff'});
      expect(rules[1], {
        'port': <int>[53],
        'action': 'hijack-dns',
      });
      expect(rules[2], {'protocol': 'dns', 'action': 'hijack-dns'});
      expect(rules[3], {
        'ip_cidr': <String>['204.11.2.216/32'],
        'outbound': 'direct',
      });
      expect(rules[4], {
        'rule_set': 'geosite-category-ru',
        'outbound': 'direct',
      });
      expect(rules.last, {
        'ip_cidr': <String>[fakeIpV4Range],
        'outbound': 'proxy',
      });
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
