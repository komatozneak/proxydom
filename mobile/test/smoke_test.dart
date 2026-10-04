import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:proxydom/core/app_locale.dart';
import 'package:proxydom/core/config.dart';
import 'package:proxydom/core/result.dart';
import 'package:proxydom/core/retry_policy.dart';
import 'package:proxydom/core/theme.dart';
import 'package:proxydom/core/extensions.dart';
import 'package:proxydom/features/home/presentation/home_screen.dart';
import 'package:proxydom/features/home/presentation/widgets/server_card.dart';
import 'package:proxydom/features/settings/data/split_tunnel_prefs.dart';
import 'package:proxydom/features/vpn/data/vpn_config.dart';
import 'package:proxydom/features/vpn/data/vpn_controller.dart';
import 'package:proxydom/features/vpn/data/vpn_service_config.dart';
import 'package:proxydom/l10n/app_localizations.dart';

/// Minimal valid Reality candidate for smoke fixtures (schema_version 1).
Map<String, dynamic> _xrayCandidate({
  String id = 'de-1',
  String host = 'vpn-dev.example',
  int port = 443,
  String uuid = '12345678-1234-1234-1234-123456789012',
  String? flow = 'xtls-rprx-vision',
  String transport = 'tcp',
  String serverName = 'example.com',
  String publicKey = 'pk',
  String shortId = 'abcd',
  String fingerprint = 'chrome',
  String? label,
}) =>
    {
      'id': id,
      'label': label ?? 'Node $id',
      'host': host,
      'port': port,
      'protocol': 'vless',
      'uuid': uuid,
      'flow': flow,
      'transport': transport,
      'security': 'reality',
      'server_name': serverName,
      'public_key': publicKey,
      'short_id': shortId,
      'fingerprint': fingerprint,
      'spider_x': '/',
    };

Map<String, dynamic> _vpnJson({
  String username = 'test_user',
  List<String> links = const [],
  int expire = 1785654092,
  String? nodeHost,
  Map<String, dynamic>? candidate,
}) =>
    {
      'username': username,
      'links': links,
      'expire': expire,
      if (nodeHost != null) 'node_host': nodeHost,
      'xray_profile': {
        'schema_version': 1,
        'candidates': [candidate ?? _xrayCandidate()],
      },
    };

void main() {
  testWidgets('Home screen shows Connect button when not connected',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const vpnChannel = MethodChannel('proxydom/vpn');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(vpnChannel, (call) async {
      if (call.method == 'getStatus') return 'idle';
      if (call.method == 'getLastError') return '';
      if (call.method == 'listLauncherApps') {
        return [
          {'packageName': 'ru.oneme.app', 'label': 'MAX'},
        ];
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(vpnChannel, null);
    });

    SharedPreferences.setMockInitialValues({});
    AppLocale.set(const Locale('ru'));

    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Pump Home directly — full ProxyDomApp + anonymous bootstrap races in tests
    // (HttpClient mocked to 400) and redirects away from /home.
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    // The terminal head sets its fields in caps.
    expect(find.text('НЕ ПОДКЛЮЧЕНО'), findsOneWidget);
    expect(find.byType(ServerCard), findsNothing);
    expect(find.text('Что работает без VPN?'), findsNothing);
    expect(find.text('1 / 1'), findsNothing);
    expect(
      await SplitTunnelPrefs.loadDisallowedPackages(),
      contains('ru.oneme.app'),
    );
    // ↓/↑ live only in shade notification — not on Home.
    expect(find.text('Скачивание'), findsNothing);
    expect(find.text('Отправка'), findsNothing);
    // Session clock is inside ServerCard only when connected.
    expect(find.text('СЕССИЯ'), findsNothing);

    debugDefaultTargetPlatformOverride = null;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('iOS Home hides NoVPN row and Apps pin', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    const vpnChannel = MethodChannel('proxydom/vpn');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(vpnChannel, (call) async {
      if (call.method == 'getStatus') return 'idle';
      if (call.method == 'getLastError') return '';
      if (call.method == 'listLauncherApps') {
        return [
          {'packageName': 'ru.oneme.app', 'label': 'MAX'},
        ];
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(vpnChannel, null);
    });

    SharedPreferences.setMockInitialValues({});
    AppLocale.set(const Locale('ru'));

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('Что работает без VPN?'), findsNothing);
    expect(find.text('1 / 1'), findsNothing);
    expect(find.text('0 / 0'), findsNothing);

    debugDefaultTargetPlatformOverride = null;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  test('VpnConfig.fromJson парсит mock-ответ от backend', () {
    final config = VpnConfig.fromJson(
      _vpnJson(
        links: ['vless://abc@server:443?type=tcp#test_user'],
        candidate: _xrayCandidate(
          host: 'vpn-dev.example',
          publicKey: 'pk',
          shortId: 'abcd',
          fingerprint: 'chrome',
        ),
      ),
    );
    expect(config.username, 'test_user');
    expect(config.links, hasLength(1));
    expect(config.xrayProfile!.schemaVersion, 1);
    expect(config.xrayProfile!.candidates, hasLength(1));
    final primary = config.primaryCandidate;
    expect(primary.host, 'vpn-dev.example');
    expect(primary.port, 443);
    expect(primary.security, 'reality');
    expect(primary.publicKey, 'pk');
    expect(primary.fingerprint, 'chrome');
    expect(config.expire.year, greaterThan(2025));
    expect(config.expire.isUtc, true);
  });

  group('VpnController', () {
    const channel = MethodChannel('proxydom/vpn');
    final List<MethodCall> log = <MethodCall>[];

    setUp(() {
      log.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        log.add(call);
        if (call.method == 'getStatus') return 'idle';
        if (call.method == 'requestPermission') return true;
        return true;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('stop() вызывает MethodChannel stop', () async {
      final result = await VpnController.instance.stop();
      expect(result, true);
      expect(log.last.method, 'stop');
      expect(log.last.arguments, {'reason': 'user_tap'});
    });

    test('wipeSession() sends one tagged native wipe', () async {
      final result = await VpnController.instance.wipeSession(
        reason: 'identity_change',
      );
      expect(result, true);
      expect(log, hasLength(1));
      expect(log.single.method, 'wipeSession');
      expect(log.single.arguments, {'reason': 'identity_change'});
    });

    test('getStatus() возвращает idle (мок)', () async {
      final status = await VpnController.instance.getStatus();
      expect(status, VpnNativeStatus.idle);
      expect(log.last.method, 'getStatus');
    });

    test('requestPermission() вызывает MethodChannel и возвращает true',
        () async {
      final granted = await VpnController.instance.requestPermission();
      expect(granted, true);
      expect(log.last.method, 'requestPermission');
    });

    test('requestPermission() при MissingPluginException возвращает true',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      final granted = await VpnController.instance.requestPermission();
      expect(granted, true);
    });

    test(
      'start() вызывает MethodChannel с правильными аргументами',
      () async {
        SharedPreferences.setMockInitialValues({});
        final config = VpnConfig.fromJson({
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
        final ok = await VpnController.instance.start(config);
        expect(ok, true);
        expect(log.last.method, 'start');
        final args = log.last.arguments as Map;
        expect(args.containsKey('paramsJson'), true);
        final paramsString = args['paramsJson'] as String;
        expect(paramsString.contains('"vpnCore":"hysteria"'), true);
        expect(paramsString.contains('hy2.example:443'), true);
        expect(paramsString.contains('hy2.example'), true);
        expect(paramsString.contains('user:pass'), true);
      },
    );

    test(
      'start() без hysteria_profile бросает VpnControllerException',
      () async {
        final config = VpnConfig(
          username: 'empty',
          links: const [],
          expire: DateTime.utc(2026, 7, 1),
          activeCore: VpnActiveCore.hysteria,
        );
        expect(
          () => VpnController.instance.start(config),
          throwsA(isA<VpnControllerException>()),
        );
      },
    );
  });

  group('VpnServiceConfig', () {
    test('fromVpnConfig использует TUN defaults и primary candidate', () {
      final cfg = VpnConfig.fromJson(
        _vpnJson(
          links: ['vless://...'],
          candidate: _xrayCandidate(host: 'unknown-vps.example'),
        ),
      );
      final service = VpnServiceConfig.fromVpnConfig(cfg);
      expect(service.mtu, 1500);
      expect(service.address, '10.255.255.1');
      expect(service.addressPrefix, 30);
      expect(service.routes, ['0.0.0.0/0']);
      expect(service.dnsServers, ['10.255.255.2']);
      expect(service.outboundServer, 'unknown-vps.example');
      expect(service.outboundServerPort, 443);
      expect(service.sessionName, 'Прокси Дом');
      expect(service.displayLabel, 'Прокси Дом');
      expect(service.outboundType, 'vless');
    });

    test('fromVpnConfig берёт Reality fields из xray candidate', () {
      final config = VpnConfig.fromJson(
        _vpnJson(
          username: 'real_user',
          candidate: _xrayCandidate(
            host: 'real-server.example',
            port: 8443,
            uuid: 'real-uuid-1234',
            flow: 'xtls-rprx-vision',
            serverName: 'real-sni.example',
            fingerprint: 'safari',
            publicKey: 'realpublickey123',
            shortId: 'realshortid',
          ),
        ),
      );
      final service = VpnServiceConfig.fromVpnConfig(config);
      expect(service.address, '10.255.255.1');
      expect(service.addressPrefix, 30);
      expect(service.routes, contains('0.0.0.0/0'));
      expect(service.routes, isNot(contains('::/0')));
      expect(service.sessionName, 'Прокси Дом');
      expect(service.outboundType, 'vless');
      expect(service.outboundServer, 'real-server.example');
      expect(service.outboundServerPort, 8443);
      expect(service.outboundUuid, 'real-uuid-1234');
      expect(service.outboundTlsFingerprint, 'safari');
      expect(service.outboundTlsPublicKey, 'realpublickey123');
      expect(service.outboundTlsShortId, 'realshortid');
      expect(service.outboundTlsSni, 'real-sni.example');
    });

    test('resolveVpnDisplayLabel: node_host maps to known place over outbound',
        () {
      final config = VpnConfig.fromJson(
        _vpnJson(
          username: 'u_3',
          nodeHost: '185.139.228.192',
          candidate: _xrayCandidate(
            host: 'cdn-front.example',
            uuid: 'uuid-1',
            flow: null,
          ),
        ),
      );
      expect(resolveVpnDisplayLabel(config), 'Нидерланды');
      final service = VpnServiceConfig.fromVpnConfig(config);
      expect(service.displayLabel, 'Нидерланды');
      expect(service.sessionName, 'Прокси Дом');
    });

    test('resolveVpnDisplayLabel: unknown host is brand, not Сервер 1', () {
      final config = VpnConfig.fromJson(
        _vpnJson(
          username: 'u_3',
          candidate: _xrayCandidate(
            host: 'unknown-vps.example',
            uuid: 'uuid-1',
            flow: null,
          ),
        ),
      );
      expect(resolveVpnDisplayLabel(config), 'Прокси Дом');
      expect(resolveVpnDisplayLabel(config), isNot(contains('Сервер')));
      expect(
        VpnServiceConfig.fromVpnConfig(config).displayLabel,
        'Прокси Дом',
      );
    });

    test('resolveVpnDisplayLabel: explicit displayLabel wins', () {
      final config = VpnConfig.fromJson(
        _vpnJson(
          username: 'u_3',
          nodeHost: '185.139.228.192',
          candidate: _xrayCandidate(
            host: '185.139.228.192',
            uuid: 'uuid-1',
            flow: null,
          ),
        ),
      );
      expect(
        resolveVpnDisplayLabel(config, displayLabel: 'Авто · Германия'),
        'Авто · Германия',
      );
    });

    test('toMap() возвращает flat keys (без вложенного outbound)', () {
      final cfg = VpnConfig.fromJson(
        _vpnJson(
          username: 'flat',
          candidate: _xrayCandidate(
            host: 's',
            uuid: 'u',
            flow: null,
          ),
        ),
      );
      final service = VpnServiceConfig.fromVpnConfig(cfg);
      final map = service.toMap();
      expect(map.containsKey('outbound'), false);
      expect(map['outboundServer'], 's');
      expect(map['outboundServerPort'], 443);
      expect(map['outboundUuid'], 'u');
      expect(map['controlPlaneHosts'], isEmpty);
      expect(map['egressHosts'], ['s']);
    });
  });

  test('AppConfig.baseUrl defaults to prod VPS', () {
    expect(AppConfig.baseUrl, isNotEmpty);
    expect(AppConfig.baseUrl, contains('/v2'));
    expect(AppConfig.baseUrl, AppConfig.vpsBaseUrl);
  });

  test('AppConfig.vpsBaseUrl points to RF control-plane prod backend', () {
    expect(
      AppConfig.vpsBaseUrl,
      'https://api.proxydom.su/v2',
    );
    expect(AppConfig.vpsBaseUrl, startsWith('https://'));
    expect(AppConfig.vpsBaseUrl, contains('/v2'));
    expect(AppConfig.vpsIpv4, '195.225.108.81');
  });

  test('AppConfig dev switch via APP_ENV=dev dart-define', () {
    expect(AppConfig.baseUrlForEnvironment('prod'), AppConfig.vpsBaseUrl);
    expect(AppConfig.baseUrlForEnvironment('dev'), AppConfig.androidBaseUrl);
    expect(AppConfig.baseUrlForEnvironment('dev'),
        isNot(equals(AppConfig.vpsBaseUrl)));
  });

  group('AppTheme (Material 3)', () {
    test('light тема использует Material 3', () {
      expect(AppTheme.light.useMaterial3, true);
      expect(AppTheme.light.brightness, Brightness.light);
      // ColorScheme.fromSeed derives primary from seed via tonal palette,
      // so seed and primary are not equal — we only verify the theme is M3.
    });

    test('dark тема использует Material 3', () {
      expect(AppTheme.dark.useMaterial3, true);
      expect(AppTheme.dark.brightness, Brightness.dark);
    });

    test('light и dark имеют разные colorScheme', () {
      expect(
        AppTheme.light.colorScheme.surface,
        isNot(equals(AppTheme.dark.colorScheme.surface)),
      );
      expect(
        AppTheme.light.colorScheme.onSurface,
        isNot(equals(AppTheme.dark.colorScheme.onSurface)),
      );
    });

    test('AppBrand constants заданы', () {
      // Mono mark charcoal + zinc.
      expect(AppBrand.primary, const Color(0xFF1A1A1A));
      expect(AppBrand.success, const Color(0xFF558B2F));
      expect(AppBrand.warning, const Color(0xFF6B6B73));
      expect(AppBrand.accent, const Color(0xFF1A1A1A));
      expect(AppBrand.error, const Color(0xFF1A1A1A));
    });

    test('textTheme настроен для всех уровней', () {
      final tt = AppTheme.light.textTheme;
      expect(tt.displayLarge, isNotNull);
      expect(tt.headlineLarge, isNotNull);
      expect(tt.titleLarge, isNotNull);
      expect(tt.bodyLarge, isNotNull);
      expect(tt.labelLarge, isNotNull);
    });

    test('component themes заданы (AppBar/FilledButton/Card)', () {
      expect(AppTheme.light.appBarTheme.backgroundColor,
          AppTheme.light.colorScheme.surface);
      expect(AppTheme.light.filledButtonTheme.style, isNotNull);
      expect(AppTheme.light.cardTheme.elevation, 0);
      expect(AppTheme.light.cardTheme.shape, isA<RoundedRectangleBorder>());
    });

    test('vpnStatusColor extension возвращает ожидаемые brand-цвета', () {
      final scheme = AppTheme.light.colorScheme;
      expect(scheme.vpnStatusColor('connected'), AppBrand.success);
      expect(scheme.vpnStatusColor('connecting'), AppBrand.warning);
      expect(scheme.vpnStatusColor('error'), AppBrand.destructive);
      expect(scheme.vpnStatusColor('unknown'), scheme.outline);
    });
  });

  group('RetryPolicy', () {
    test('выполняется с первой попытки если нет ошибки', () async {
      final policy = RetryPolicy(maxAttempts: 3);
      var attempts = 0;
      final result = await policy.execute(() async {
        attempts++;
        return 'ok';
      });
      expect(attempts, 1);
      expect(result, 'ok');
    });

    test('retry на transient ошибках до maxAttempts', () async {
      final policy = RetryPolicy(
        maxAttempts: 3,
        initialDelay: const Duration(milliseconds: 10),
      );
      var attempts = 0;
      final result = await policy.execute(() async {
        attempts++;
        if (attempts < 3) throw Exception('transient');
        return 'ok';
      });
      expect(attempts, 3);
      expect(result, 'ok');
    });

    test('бросает последнюю ошибку после maxAttempts', () async {
      final policy = RetryPolicy(
        maxAttempts: 3,
        initialDelay: const Duration(milliseconds: 10),
      );
      var attempts = 0;
      await expectLater(
        policy.execute(() async {
          attempts++;
          throw Exception('always fails');
        }),
        throwsException,
      );
      expect(attempts, 3);
    });

    test('shouldRetry=false → без retry', () async {
      final policy = RetryPolicy(maxAttempts: 3);
      var attempts = 0;
      await expectLater(
        policy.execute(
          () async {
            attempts++;
            throw Exception('user error');
          },
          shouldRetry: (_) async => false,
        ),
        throwsException,
      );
      expect(attempts, 1);
    });

    test('backoff экспоненциальный', () {
      final policy = RetryPolicy(
        initialDelay: const Duration(milliseconds: 100),
        backoffMultiplier: 2.0,
        maxDelay: const Duration(seconds: 10),
      );
      expect(policy.delayFor(1), Duration.zero);
      expect(policy.delayFor(2), const Duration(milliseconds: 200));
      expect(policy.delayFor(3), const Duration(milliseconds: 400));
    });

    test('Result<T> when() раскрывает success и failure', () {
      const success = Success<int>(42);
      const failure = Failure<int>('error');

      expect(success.isSuccess, true);
      expect(failure.isFailure, true);
      expect(success.valueOrNull, 42);
      expect(failure.valueOrNull, null);

      final sValue = success.when<int>(
        success: (v) => v * 2,
        failure: (_, __) => -1,
      );
      final fValue = failure.when<int>(
        success: (v) => v * 2,
        failure: (_, __) => -1,
      );
      expect(sValue, 84);
      expect(fValue, -1);
    });
  });

}
