import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teremok_connect/features/settings/data/split_tunnel_prefs.dart';
import 'package:teremok_connect/features/vpn/data/vpn_config.dart';
import 'package:teremok_connect/features/vpn/data/vpn_controller.dart';
import 'package:teremok_connect/features/vpn/data/vpn_route_policy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('stripForceProxySuffixes drops YouTube/Google keeps VK', () {
    expect(
      stripForceProxySuffixes([
        'vk.com',
        'youtube.com',
        'www.googlevideo.com',
        'example.com',
        'google.com',
      ]),
      ['example.com', 'vk.com'],
    );
  });

  test('isSmartForceProxyHost matches suffix', () {
    expect(isSmartForceProxyHost('youtube.com'), isTrue);
    expect(isSmartForceProxyHost('m.youtube.com'), isTrue);
    expect(isSmartForceProxyHost('notyoutube.com'), isFalse);
    expect(isSmartForceProxyHost('vk.com'), isFalse);
  });

  test('buildStartParamsJson ships RF defaults and strips YouTube', () async {
    SharedPreferences.setMockInitialValues({});
    final defaultJson = await VpnController.instance.buildStartParamsJson(
      _hy2Config(),
    );
    final defaultMap = jsonDecode(defaultJson) as Map<String, dynamic>;
    final defaultSuffixes = List<String>.from(
      defaultMap['directDomainSuffixes'] as List<dynamic>,
    );
    expect(defaultSuffixes, contains('vk.com'));
    expect(defaultSuffixes, contains('yandex.ru'));
    expect(defaultSuffixes, contains('ozon.ru'));
    expect(defaultSuffixes, contains('wildberries.ru'));
    expect(defaultSuffixes, isNot(contains('tiktok.com')));

    await SplitTunnelPrefs.setOsnovnyeEnabled('vk', true);
    await SplitTunnelPrefs.addSite(domain: 'example.com');
    await SplitTunnelPrefs.addSite(domain: 'youtube.com');
    final wired = jsonDecode(
      await VpnController.instance.buildStartParamsJson(_hy2Config()),
    ) as Map<String, dynamic>;
    final suffixes = List<String>.from(
      wired['directDomainSuffixes'] as List<dynamic>,
    );
    expect(suffixes, contains('vk.com'));
    expect(suffixes, contains('example.com'));
    expect(suffixes, isNot(contains('youtube.com')));
    expect(suffixes, isNot(contains('googlevideo.com')));
    expect(suffixes, isNot(contains('google.com')));
    expect(suffixes, isNot(contains('tiktok.com')));
  });
}

VpnConfig _hy2Config() {
  return VpnConfig.fromJson({
    'username': 'test_user',
    'links': const <String>[],
    'expire': 1785654092,
    'active_core': 'hysteria',
    'hysteria_profile': {
      'schema_version': 1,
      'node_id': 'eu-hy2-1',
      'server': 'hy2.example:443',
      'auth': 'user:pass',
      'username': 'user',
      'sni': 'hy2.example',
      'socks_listen': '127.0.0.1:10808',
    },
  });
}
