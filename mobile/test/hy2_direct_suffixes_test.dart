import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:proxydom/features/settings/data/split_tunnel_prefs.dart';
import 'package:proxydom/features/vpn/data/hysteria_profile.dart';
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

  test('normalizeRouteSuffixes keeps user domains', () {
    expect(
      normalizeRouteSuffixes([
        'vk.com',
        ' YouTube.com ',
        'example.com',
        'example.com',
      ]),
      ['example.com', 'vk.com', 'youtube.com'],
    );
  });

  test('buildHy2StartParamsJson ships RF defaults and user domains', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
    final defaultJson = await VpnController.instance.buildHy2StartParamsJson(
      _hy2Profile(),
    );
    final defaultMap = jsonDecode(defaultJson) as Map<String, dynamic>;
    final defaultSuffixes = List<String>.from(
      defaultMap['directDomainSuffixes'] as List<dynamic>,
    );
    expect(defaultSuffixes, contains('vk.com'));
    expect(defaultSuffixes, contains('yandex.ru'));
    expect(defaultSuffixes, contains('ozon.ru'));
    expect(defaultSuffixes, contains('wildberries.ru'));
    expect(defaultSuffixes, contains('yoomoney.ru'));
    expect(defaultSuffixes, contains('rustore.ru'));

    await SplitTunnelPrefs.setOsnovnyeEnabled('vk', true);
    await SplitTunnelPrefs.addSite(domain: 'example.com');
    await SplitTunnelPrefs.addSite(domain: 'gw.company-net.ru');
    final wired = jsonDecode(
      await VpnController.instance.buildHy2StartParamsJson(_hy2Profile()),
    ) as Map<String, dynamic>;
    final suffixes = List<String>.from(
      wired['directDomainSuffixes'] as List<dynamic>,
    );
    expect(suffixes, contains('vk.com'));
    expect(suffixes, contains('example.com'));
    expect(suffixes, contains('gw.company-net.ru'));
  });

  test('fm timer keys ride in start params and an empty profile omits them',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
    final plain = jsonDecode(
      await VpnController.instance.buildHy2StartParamsJson(_hy2Profile()),
    ) as Map<String, dynamic>;
    expect(plain, isNot(contains('hysteriaCongestion')));
    expect(plain, isNot(contains('hysteriaMaxIdleTimeout')));
    expect(plain, isNot(contains('hysteriaKeepAlivePeriod')));
    expect(plain, isNot(contains('hysteriaFmDeclared')));
    expect(plain, isNot(contains('hysteriaBandwidthUp')));

    final declared = jsonDecode(
      await VpnController.instance.buildHy2StartParamsJson(
        _hy2Profile(
          congestion: 'brutal',
          bbrProfile: 'aggressive',
          maxIdleTimeout: '20',
          keepAlivePeriod: '10',
          fmDeclared: 'quicParams.maxIdleTimeout,quicParams.brutalUp',
        ),
      ),
    ) as Map<String, dynamic>;
    expect(declared['hysteriaCongestion'], 'brutal');
    expect(declared['hysteriaBbrProfile'], 'aggressive');
    expect(declared['hysteriaMaxIdleTimeout'], '20');
    expect(declared['hysteriaKeepAlivePeriod'], '10');
    expect(
      declared['hysteriaFmDeclared'],
      'quicParams.maxIdleTimeout,quicParams.brutalUp',
    );
    expect(declared['hysteriaFmDeclared'], isNot(contains('2000')));
    expect(declared, isNot(contains('hysteriaBandwidthUp')));

    final started = await _captureStartParams(
      () => VpnController.instance.startHysteria(
        _hy2Profile(maxIdleTimeout: '1', congestion: 'brutal'),
      ),
    );
    expect(started['hysteriaMaxIdleTimeout'], '1');
    expect(started['hysteriaCongestion'], 'brutal');
    expect(started, isNot(contains('hysteriaBandwidthUp')));
  });

  test('Android params keep hyDialer suffixes and Apps bypass', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
    await SplitTunnelPrefs.setDisallowedPackage('ru.yandex.taxi', true);
    final map = jsonDecode(
      await VpnController.instance.buildHy2StartParamsJson(_hy2Profile()),
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
      await VpnController.instance.buildHy2StartParamsJson(_hy2Profile()),
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
      _hy2Profile(),
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

HysteriaProfile _hy2Profile({
  String congestion = '',
  String bbrProfile = '',
  String maxIdleTimeout = '',
  String keepAlivePeriod = '',
  String fmDeclared = '',
}) {
  return HysteriaProfile(
    schemaVersion: 1,
    nodeId: 'eu-hy2-1',
    server: 'hy2.example:443',
    auth: 'user:pass',
    username: 'user',
    sni: 'hy2.example',
    socksListen: '127.0.0.1:10808',
    congestion: congestion,
    bbrProfile: bbrProfile,
    maxIdleTimeout: maxIdleTimeout,
    keepAlivePeriod: keepAlivePeriod,
    fmDeclared: fmDeclared,
  );
}
