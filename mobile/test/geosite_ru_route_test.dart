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
}

void main() {
  test('local RU rule-sets route to direct before final proxy', () {
    final json = jsonDecode(
      buildRuntimeSingBoxJson(
        config: _sampleVpnConfig(),
        service: VpnServiceConfig.fromVpnConfig(_sampleVpnConfig()),
        localRulePaths: {
          'geosite-category-ru': '/tmp/geosite-category-ru.srs',
          'geosite-tld-ru': '/tmp/geosite-tld-ru.srs',
          'geoip-ru': '/tmp/geoip-ru.srs',
        },
      ),
    ) as Map<String, dynamic>;

    final route = json['route'] as Map<String, dynamic>;
    final rules = route['rules'] as List<dynamic>;
    final ruleSets = route['rule_set'] as List<dynamic>;

    expect(
      ruleSets.map((e) => (e as Map)['tag']),
      containsAll(<String>[
        'geosite-category-ru',
        'geosite-tld-ru',
      ]),
    );
    expect(
      ruleSets.map((e) => (e as Map)['tag']),
      isNot(contains('geoip-ru')),
    );
    expect(
      ruleSets.every((e) => (e as Map)['type'] == 'local'),
      isTrue,
    );

    final directRuleSets = rules
        .whereType<Map>()
        .where((r) => r['outbound'] == 'direct' && r.containsKey('rule_set'))
        .map((r) => r['rule_set'])
        .toList();
    expect(
      directRuleSets,
      containsAll(<String>[
        'geosite-category-ru',
        'geosite-tld-ru',
      ]),
    );
    expect(directRuleSets, isNot(contains('geoip-ru')));

    expect(route['final'], 'proxy');
    expect(jsonEncode(json).contains('githubusercontent'), isFalse);
  });
}
