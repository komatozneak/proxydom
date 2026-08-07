import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teremok_connect/features/settings/data/split_tunnel_prefs.dart';
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
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('domain normalize', () {
    test('accepts example.com', () {
      final r = normalizeSplitTunnelDomain(' Example.COM. ');
      expect(r, isA<DomainNormalizeOk>());
      expect((r as DomainNormalizeOk).domain, 'example.com');
    });

    test('ensurePresetSites seeds full catalog and keeps customs', () async {
      await SplitTunnelPrefs.addSite(domain: 'twitch.tv', label: 'Twitch');
      await SplitTunnelPrefs.ensurePresetSites();
      final sites = await SplitTunnelPrefs.loadSites();
      expect(sites.where((s) => s.isPreset).length, kSplitTunnelPresets.length);
      expect(sites.any((s) => s.domain == 'whatsapp.com'), isTrue);
      expect(sites.any((s) => s.domain == 'claude.ai'), isTrue);
      expect(sites.any((s) => s.domain == 'gemini.google.com'), isTrue);
      expect(
        sites.firstWhere((s) => s.domain == 'gemini.google.com').subtitle,
        'Нейросеть',
      );
      expect(
        kSplitTunnelDomainAliases['gemini.google.com'],
        containsAll([
          'generativelanguage.googleapis.com',
          'google.com',
          'gstatic.com',
        ]),
      );
      expect(
        kSplitTunnelDomainAliases['telegram.org'],
        containsAll(['api.telegram.org', 'telegra.ph']),
      );
      expect(
        kSplitTunnelProxyIpCidrs['telegram.org'],
        contains('149.154.160.0/20'),
      );
      expect(sites.any((s) => s.domain == 'twitch.tv' && !s.isPreset), isTrue);
      final ig = sites.firstWhere((s) => s.domain == 'instagram.com');
      expect(ig.subtitle, contains('Facebook'));
    });

    test('rejects scheme/path/ip/wildcard/single-label/non-ascii', () {
      expect(
        normalizeSplitTunnelDomain('https://example.com'),
        isA<DomainNormalizeErr>(),
      );
      expect(
        normalizeSplitTunnelDomain('example.com/path'),
        isA<DomainNormalizeErr>(),
      );
      expect(
        normalizeSplitTunnelDomain('1.2.3.4'),
        isA<DomainNormalizeErr>(),
      );
      expect(
        normalizeSplitTunnelDomain('*.example.com'),
        isA<DomainNormalizeErr>(),
      );
      expect(
        normalizeSplitTunnelDomain('localhost'),
        isA<DomainNormalizeErr>(),
      );
      expect(
        normalizeSplitTunnelDomain('сайт.рф'),
        isA<DomainNormalizeErr>(),
      );
    });
  });

  group('prefs defaults', () {
    test('bundled RU defaults ON', () async {
      expect(await SplitTunnelPrefs.isBundledRuEnabled(), isTrue);
    });

    test('custom list empty; add/toggle/pending', () async {
      expect(await SplitTunnelPrefs.loadSites(), isEmpty);
      final added = await SplitTunnelPrefs.addSite(domain: 'news.example.org');
      expect(added, isA<DomainNormalizeOk>());
      expect(await SplitTunnelPrefs.hasPendingChanges(), isTrue);

      var sites = await SplitTunnelPrefs.loadSites();
      expect(sites.single.domain, 'news.example.org');
      await SplitTunnelPrefs.updateSite(sites.single.copyWith(enabled: false));
      sites = await SplitTunnelPrefs.loadSites();
      expect(sites.single.enabled, isFalse);
      expect(await SplitTunnelPrefs.enabledDomainSuffixes(), isEmpty);

      await SplitTunnelPrefs.markApplied();
      expect(await SplitTunnelPrefs.hasPendingChanges(), isFalse);
    });

    test('telegram enabled expands DC ip_cidr list', () async {
      await SplitTunnelPrefs.ensurePresetSites();
      final sites = await SplitTunnelPrefs.loadSites();
      final tg = sites.firstWhere((s) => s.domain == 'telegram.org');
      await SplitTunnelPrefs.updateSite(tg.copyWith(enabled: true));
      for (final s in await SplitTunnelPrefs.loadSites()) {
        if (s.domain != 'telegram.org' && s.enabled) {
          await SplitTunnelPrefs.updateSite(s.copyWith(enabled: false));
        }
      }
      final cidrs = await SplitTunnelPrefs.enabledProxyIpCidrs();
      expect(cidrs, contains('149.154.160.0/20'));
      expect(cidrs, contains('91.108.56.0/22'));
      final suffixes = await SplitTunnelPrefs.enabledDomainSuffixes();
      expect(suffixes, contains('api.telegram.org'));
    });

    test('duplicate rejected', () async {
      await SplitTunnelPrefs.addSite(domain: 'a.example.com');
      final dup = await SplitTunnelPrefs.addSite(domain: 'a.example.com');
      expect(dup, isA<DomainNormalizeErr>());
      expect(
        (dup as DomainNormalizeErr).kind,
        DomainNormalizeErrorKind.duplicate,
      );
    });
  });

  group('sing-box config hooks', () {
    final paths = {
      'geosite-category-ru': '/tmp/geosite-category-ru.srs',
      'geosite-tld-ru': '/tmp/geosite-tld-ru.srs',
      'geoip-ru': '/tmp/geoip-ru.srs',
    };

    test('bundled ON keeps three local rule_sets', () {
      final json = jsonDecode(
        buildRuntimeSingBoxJson(
          config: _sampleVpnConfig(),
          service: VpnServiceConfig.fromVpnConfig(_sampleVpnConfig()),
          localRulePaths: paths,
          includeBundledRuRuleSets: true,
        ),
      ) as Map<String, dynamic>;
      final route = json['route'] as Map<String, dynamic>;
      expect(route['rule_set'], isNotNull);
      expect(jsonEncode(json).contains('githubusercontent'), isFalse);
      expect(json['dns'].toString().contains('fakeip'), isFalse);
    });

    test('bundled OFF omits rule_set direct rules', () {
      final json = jsonDecode(
        buildRuntimeSingBoxJson(
          config: _sampleVpnConfig(),
          service: VpnServiceConfig.fromVpnConfig(_sampleVpnConfig()),
          localRulePaths: paths,
          includeBundledRuRuleSets: false,
          customDirectDomainSuffixes: const ['example.com'],
        ),
      ) as Map<String, dynamic>;
      final route = json['route'] as Map<String, dynamic>;
      expect(route.containsKey('rule_set'), isFalse);
      final rules = route['rules'] as List<dynamic>;
      final hasRu = rules.any(
        (r) => r is Map && r['rule_set'] == 'geosite-category-ru',
      );
      expect(hasRu, isFalse);
      final custom = rules.whereType<Map>().firstWhere(
            (r) => r['domain_suffix'] != null,
          );
      expect(custom['domain_suffix'], contains('example.com'));
      expect(custom['outbound'], 'direct');
      expect(route['final'], 'proxy');
    });
  });
}
