import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:proxydom/features/settings/data/split_tunnel_prefs.dart';
import 'package:proxydom/features/vpn/data/vpn_config.dart';
import 'package:proxydom/features/vpn/data/vpn_controller.dart';
import 'package:proxydom/features/vpn/data/vpn_route_policy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('proxydom/vpn'),
      null,
    );
  });

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
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
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
    expect(defaultSuffixes, contains('yoomoney.ru'));
    expect(defaultSuffixes, contains('rustore.ru'));

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

  test('Android params keep hyDialer suffixes and Apps bypass', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
    await SplitTunnelPrefs.setDisallowedPackage('ru.yandex.taxi', true);
    final map = jsonDecode(
      await VpnController.instance.buildStartParamsJson(_hy2Config()),
    ) as Map<String, dynamic>;
    expect(map, contains('directDomainSuffixes'));
    expect(
      List<String>.from(map['disallowedApplications'] as List<dynamic>),
      contains('ru.yandex.taxi'),
    );
    expect(map, isNot(contains('iosCustomResolutionHosts')));
    expect(map, isNot(contains('iosCatalogResolutionHosts')));
  });

  test('iOS auto params use exact host groups and no Android fields', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    SharedPreferences.setMockInitialValues({});
    await SplitTunnelPrefs.addSite(domain: 'api.example.com');
    await SplitTunnelPrefs.setDisallowedPackage('com.example.android', true);

    final map = jsonDecode(
      await VpnController.instance.buildStartParamsJson(_hy2Config()),
    ) as Map<String, dynamic>;
    expect(map, isNot(contains('directDomainSuffixes')));
    expect(map, isNot(contains('disallowedApplications')));
    expect(
      List<String>.from(map['iosCustomResolutionHosts'] as List<dynamic>),
      ['api.example.com'],
    );
    expect(
      List<String>.from(map['iosCatalogResolutionHosts'] as List<dynamic>),
      contains('static.rutube.ru'),
    );
  });

  test('iOS manual params use the same exact-host contract', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    SharedPreferences.setMockInitialValues({});
    await SplitTunnelPrefs.addSite(domain: 'exact.example.com');
    String? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('proxydom/vpn'),
      (call) async {
        if (call.method == 'start') {
          final args = Map<Object?, Object?>.from(call.arguments as Map);
          captured = args['paramsJson'] as String?;
        }
        return true;
      },
    );

    await VpnController.instance.startHysteria(
      _hy2Config().hysteriaProfile!,
    );
    final map = jsonDecode(captured!) as Map<String, dynamic>;
    expect(map, isNot(contains('directDomainSuffixes')));
    expect(map, isNot(contains('disallowedApplications')));
    expect(
      List<String>.from(map['iosCustomResolutionHosts'] as List<dynamic>),
      ['exact.example.com'],
    );
  });

  test('Android VLESS start sends app exclusions and no site suffixes',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
    await SplitTunnelPrefs.setDisallowedPackage('ru.yandex.taxi', true);
    final map = await _captureStartParams(
      () => VpnController.instance.startVless('{"outbounds":[]}'),
    );
    expect(map['vpnCore'], 'vless');
    expect(map['vlessConfig'], '{"outbounds":[]}');
    expect(
      List<String>.from(map['disallowedApplications'] as List<dynamic>),
      ['ru.yandex.taxi'],
    );
    expect(map, isNot(contains('directDomainSuffixes')));
    expect(await SplitTunnelPrefs.hasPendingChanges(), isTrue);
  });

  test('Android VLESS start omits an empty app list', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
    final map = await _captureStartParams(
      () => VpnController.instance.startVless('{}'),
    );
    expect(map, isNot(contains('disallowedApplications')));
    expect(map, isNot(contains('directDomainSuffixes')));
  });

  test('iOS VLESS start does not send Android app exclusions', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    SharedPreferences.setMockInitialValues({});
    await SplitTunnelPrefs.setDisallowedPackage('ru.yandex.taxi', true);
    final map = await _captureStartParams(
      () => VpnController.instance.startVless('{}'),
    );
    expect(map, isNot(contains('disallowedApplications')));
    expect(map, isNot(contains('directDomainSuffixes')));
  });
}

Future<Map<String, dynamic>> _captureStartParams(
  Future<bool> Function() start,
) async {
  String? captured;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('proxydom/vpn'),
    (call) async {
      if (call.method == 'start') {
        final args = Map<Object?, Object?>.from(call.arguments as Map);
        captured = args['paramsJson'] as String?;
      }
      return true;
    },
  );
  await start();
  return jsonDecode(captured!) as Map<String, dynamic>;
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
