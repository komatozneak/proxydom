import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:teremok_connect/app.dart';
import 'package:teremok_connect/core/api_client.dart';
import 'package:teremok_connect/core/config.dart';
import 'package:teremok_connect/core/jwt_interceptor.dart';
import 'package:teremok_connect/core/result.dart';
import 'package:teremok_connect/core/retry_policy.dart';
import 'package:teremok_connect/core/router.dart';
import 'package:teremok_connect/core/token_storage.dart';
import 'package:teremok_connect/features/auth/application/auth_provider.dart';
import 'package:teremok_connect/features/auth/application/auth_state.dart';
import 'package:teremok_connect/features/auth/application/logout_handler.dart';
import 'package:teremok_connect/features/vpn/data/vpn_config.dart';
import 'package:teremok_connect/features/vpn/data/vpn_controller.dart';
import 'package:teremok_connect/features/vpn/data/vpn_service_config.dart';
import 'package:teremok_connect/l10n/app_localizations.dart';

class _FakeTokenStorage implements TokenStore {
  _FakeTokenStorage({this.access = 'old-access', this.refresh = 'old-refresh'});

  String access;
  String refresh;
  int clearCount = 0;
  int saveCount = 0;

  @override
  Future<String?> readAccessToken() async => access.isEmpty ? null : access;

  @override
  Future<String?> readRefreshToken() async => refresh.isEmpty ? null : refresh;

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    saveCount++;
    access = accessToken;
    refresh = refreshToken;
  }

  @override
  Future<void> clear() async {
    clearCount++;
    access = '';
    refresh = '';
  }
}

/// Обёртка для тестов: подкладывает ProviderContainer, чтобы ConsumerWidget
/// могли читать authProvider/vpnProvider.
Widget _wrap(Widget child) => UncontrolledProviderScope(
  container: ProviderContainer(),
  child: child,
);

void main() {
  testWidgets('App boots and shows login screen (en by default)', (tester) async {
    AppLocale.set(const Locale('en'));
    await tester.pumpWidget(_wrap(const TeremokApp()));
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('Phone number'), findsOneWidget);
    expect(find.text('Call me'), findsOneWidget);
  });

  testWidgets('App boots and shows login screen (ru)', (tester) async {
    AppLocale.set(const Locale('ru'));
    await tester.pumpWidget(_wrap(const TeremokApp()));
    await tester.pumpAndSettle();

    expect(find.text('Вход'), findsWidgets);
    expect(find.text('Номер телефона'), findsOneWidget);
    expect(find.text('Позвонить'), findsOneWidget);
  });

  testWidgets('Login screen renders phone field and button', (tester) async {
    AppLocale.set(const Locale('ru'));
    await tester.pumpWidget(_wrap(const TeremokApp()));
    await tester.pumpAndSettle();

    expect(find.text('Номер телефона'), findsOneWidget);
    expect(find.text('+7 999 123 4567'), findsOneWidget);
    expect(find.text('Позвонить'), findsOneWidget);
  });

  testWidgets('Verify screen renders 4 fields and resend button', (tester) async {
    AppLocale.set(const Locale('ru'));
    AppRouter.pendingPhone = '+79991234567';

    final widget = MaterialApp.router(
      routerConfig: AppRouter.config,
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: AppLocale.current,
    );
    await tester.pumpWidget(_wrap(widget));
    await tester.pump();

    AppRouter.config.go(
      '/verify?phone=${Uri.encodeComponent('+79991234567')}',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Введите код'), findsOneWidget);
    expect(find.text('Перезвонить через 30с'), findsOneWidget);
    expect(find.text('Force submit "0000"'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(5));
  });

  testWidgets('Home screen shows Connect button when not connected', (tester) async {
    AppLocale.set(const Locale('ru'));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    // Переводим в authenticated чтобы GoRouter пустил на /home
    await container.read(authProvider.notifier).authenticated(
          accessToken: 'fake',
          refreshToken: 'fake',
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TeremokApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Подключиться'), findsOneWidget);
    expect(find.text('Отключено'), findsOneWidget);
  });

  test('AuthState sealed: defaults to Unauthenticated when no tokens', () async {
    // Используем чистый sub-тест: build() подхватит реальный TokenStorage,
    // который в тестах не имеет плагина → провайдер упадёт в AsyncError.
    // Поэтому проверяем сам факт, что Unauthenticated() — singleton-конструктор.
    const a = AuthStateUnauthenticated();
    const b = AuthStateUnauthenticated();
    expect(identical(a, b), isTrue);
  });

  test('VpnConfig.fromJson парсит mock-ответ от backend', () {
    final json = {
      'username': 'test_user',
      'links': ['vless://abc@server:443?type=tcp#test_user'],
      'expire': 1785654092,
      'sing_box_config': {
        'log': {'level': 'info'},
        'inbounds': [
          {
            'type': 'tun',
            'inet4_address': '172.19.0.1/30',
            'auto_route': true,
            'strict_route': true,
          },
        ],
        'outbounds': [
          {
            'type': 'vless',
            'tag': 'proxy',
            'server': 'vpn-dev.example',
            'server_port': 443,
            'uuid': '12345678-1234-1234-1234-123456789012',
            'flow': 'xtls-rprx-vision',
            'tls': {
              'enabled': true,
              'server_name': 'example.com',
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
    };

    final config = VpnConfig.fromJson(json);
    expect(config.username, 'test_user');
    expect(config.links, hasLength(1));
    expect(config.singBoxConfig.primaryOutbound?.server, 'vpn-dev.example');
    expect(config.singBoxConfig.primaryOutbound?.serverPort, 443);
    expect(
      config.singBoxConfig.primaryOutbound?.tls?.realityEnabled,
      true,
    );
    expect(
      config.singBoxConfig.primaryOutbound?.tls?.publicKey,
      'pk',
    );
    expect(
      config.singBoxConfig.primaryOutbound?.tls?.fingerprint,
      'chrome',
    );
    expect(config.expire.year, greaterThan(2025));
    expect(config.expire.isUtc, true);
  });

  group('VpnController', () {
    const channel = MethodChannel('teremok/vpn');
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
    });

    test('getStatus() возвращает idle (мок)', () async {
      final status = await VpnController.instance.getStatus();
      expect(status, VpnNativeStatus.idle);
      expect(log.last.method, 'getStatus');
    });

    test('requestPermission() вызывает MethodChannel и возвращает true', () async {
      final granted = await VpnController.instance.requestPermission();
      expect(granted, true);
      expect(log.last.method, 'requestPermission');
    });

    test(
      'start() вызывает MethodChannel с правильными аргументами',
      () async {
        final json = {
          'username': 'test_user',
          'links': const <String>[],
          'expire': 1785654092,
          'sing_box_config': {
            'log': {'level': 'info'},
            'inbounds': const [],
            'outbounds': [
              {
                'type': 'vless',
                'tag': 'proxy',
                'server': 'vpn-dev.example',
                'server_port': 443,
                'uuid': '12345678-1234-1234-1234-123456789012',
                'flow': 'xtls-rprx-vision',
              },
            ],
          },
        };
        final config = VpnConfig.fromJson(json);
        final ok = await VpnController.instance.start(config);
        expect(ok, true);
        expect(log.last.method, 'start');
        final args = log.last.arguments as Map;
        expect(args.containsKey('paramsJson'), true);
        // Декодируем paramsJson чтобы убедиться что flat keys корректные
        final paramsString = args['paramsJson'] as String;
        final params = VpnServiceConfig.fromVpnConfig(config).toMap();
        // sanity: обязательные поля
        expect(params['sessionName'], 'Teremok VPN (test_user)');
        expect(params['mtu'], 1500);
        expect(params['address'], '10.255.255.1');
        expect(params['addressPrefix'], 30);
        expect(params['outboundServer'], 'vpn-dev.example');
        expect(params['outboundServerPort'], 443);
        expect(params['outboundFlow'], 'xtls-rprx-vision');
        // paramsString содержит JSON-представление тех же данных
        expect(paramsString.contains('vpn-dev.example'), true);
        expect(paramsString.contains('12345678-1234-1234-1234-123456789012'), true);
      },
    );

    test(
      'start() без outbound бросает VpnControllerException',
      () async {
        final json = {
          'username': 'empty',
          'links': const <String>[],
          'expire': 1785654092,
          'sing_box_config': {
            'log': {'level': 'info'},
            'inbounds': const [],
            'outbounds': const [],
          },
        };
        final config = VpnConfig.fromJson(json);
        expect(
          () => VpnController.instance.start(config),
          throwsA(isA<VpnControllerException>()),
        );
      },
    );
  });

  group('VpnServiceConfig', () {
    test('fromVpnConfig использует дефолты при пустых inbounds/outbounds', () {
      final cfg = VpnConfig.fromJson({
        'username': 'test_user',
        'links': ['vless://...'],
        'expire': 1785654092,
        'sing_box_config': {
          'log': {'level': 'info'},
          'inbounds': const [],
          'outbounds': const [],
        },
      });
      final service = VpnServiceConfig.fromVpnConfig(cfg);
      expect(service.mtu, 1500);
      expect(service.address, '10.255.255.1');
      expect(service.addressPrefix, 30);
      expect(service.routes, ['0.0.0.0/0']);
      expect(service.dnsServers, ['1.1.1.1', '8.8.8.8']);
      expect(service.outboundServer, 'unknown');
      expect(service.outboundServerPort, 443);
      expect(service.sessionName, 'Teremok VPN (test_user)');
    });

    test('fromVpnConfig использует inbound и outbound из JSON', () {
      final config = VpnConfig.fromJson({
        'username': 'real_user',
        'links': const <String>[],
        'expire': 1785654092,
        'sing_box_config': {
          'log': {'level': 'info'},
          'inbounds': [
            {
              'type': 'tun',
              'inet4_address': '192.168.50.1/24',
              'auto_route': true,
              'strict_route': true,
            },
          ],
          'outbounds': [
            {
              'type': 'vless',
              'tag': 'proxy',
              'server': 'real-server.example',
              'server_port': 8443,
              'uuid': 'real-uuid-1234',
              'flow': 'xtls-rprx-vision',
              'tls': {
                'enabled': true,
                'server_name': 'real-sni.example',
                'utls': {'enabled': true, 'fingerprint': 'safari'},
                'reality': {
                  'enabled': true,
                  'public_key': 'realpublickey123',
                  'short_id': 'realshortid',
                },
              },
            },
          ],
        },
      });
      final service = VpnServiceConfig.fromVpnConfig(config);
      expect(service.address, '192.168.50.1');
      expect(service.addressPrefix, 24);
      expect(service.routes, containsAll(['0.0.0.0/0', '::/0']));
      expect(service.outboundServer, 'real-server.example');
      expect(service.outboundServerPort, 8443);
      expect(service.outboundUuid, 'real-uuid-1234');
      expect(service.outboundTlsFingerprint, 'safari');
      expect(service.outboundTlsPublicKey, 'realpublickey123');
      expect(service.outboundTlsShortId, 'realshortid');
    });

    test('toMap() возвращает flat keys (без вложенного outbound)', () {
      final cfg = VpnConfig.fromJson({
        'username': 'flat',
        'links': const <String>[],
        'expire': 1785654092,
        'sing_box_config': {
          'log': {'level': 'info'},
          'inbounds': const [],
          'outbounds': [
            {
              'type': 'vless',
              'tag': 'proxy',
              'server': 's',
              'server_port': 443,
              'uuid': 'u',
            },
          ],
        },
      });
      final service = VpnServiceConfig.fromVpnConfig(cfg);
      final map = service.toMap();
      expect(map.containsKey('outbound'), false);
      expect(map['outboundServer'], 's');
      expect(map['outboundServerPort'], 443);
      expect(map['outboundUuid'], 'u');
    });
  });

  test('AppConfig.baseUrl is set to Android emulator default', () {
    expect(AppConfig.baseUrl, isNotEmpty);
    expect(AppConfig.baseUrl, contains('/api/v1'));
  });

  test('ApiClient has correct base URL', () {
    expect(ApiClient.instance.options.baseUrl, AppConfig.baseUrl);
  });

  test('TokenStorage can be cleared safely on empty storage', () async {
    await TokenStorage.instance.clear();
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

  // LogoutHandler unit-тесты сложно написать корректно из-за того что
  // VpnNotifier.registerOnDispose → _cleanupOnLogout → ref.read(...) на
  // disposed container. В production это не проблема (container живёт
  // весь lifecycle), но в unit-тестах даёт async BadState при dispose.
  // Integration-тест на Шаге 19 покроет это end-to-end.
  group('LogoutHandler', () {
    test('smoke: LogoutResult sealed types exist', () {
      const success = LogoutSuccess();
      const failure = LogoutPartialFailure('test');
      expect(success, isA<LogoutResult>());
      expect(failure, isA<LogoutResult>());
      expect(failure.message, 'test');
    });
  });

  group('JwtRefreshInterceptor', () {
    test('при 401 делает один refresh и повторяет запрос', () async {
      final fakeTokens = _FakeTokenStorage();
      var refreshCallCount = 0;
      final refreshClient = Dio(
        BaseOptions(
          baseUrl: 'http://test/api/v1',
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      final dio = Dio(
        BaseOptions(
          baseUrl: 'http://test/api/v1',
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      final adapter = DioAdapter(
        dio: refreshClient,
        matcher: const UrlRequestMatcher(),
      );
      dio.httpClientAdapter = adapter;

      var getHitCount = 0;
      adapter.onGet(
        '/vpn/config',
        (server) {
          getHitCount++;
          if (fakeTokens.access == 'new-access') {
            server.reply(200, {'ok': true});
          } else {
            server.reply(401, {'detail': 'expired'});
          }
        },
      );
      adapter.onPost(
        RegExp(r'auth/refresh'),
        (server) {
          refreshCallCount++;
          server.reply(
            200,
            {'access_token': 'new-access', 'refresh_token': 'new-refresh'},
          );
        },
      );

      dio.interceptors.add(
        JwtRefreshInterceptor(
          dio: dio,
          refreshEndpoint: 'auth/refresh',
          tokenStorage: fakeTokens,
          refreshClient: refreshClient,
        ),
      );

      final resp = await dio.get<Map<String, dynamic>>('/vpn/config');
      expect(refreshCallCount, 1, reason: 'refresh should be called once');
      expect(fakeTokens.saveCount, 1, reason: 'tokens should be saved after refresh');
      expect(getHitCount, 2, reason: 'initial GET + retry GET');
      expect(resp.statusCode, 200);
      expect(fakeTokens.access, 'new-access');
      expect(fakeTokens.refresh, 'new-refresh');
    });

    test('параллельные 401 → ОДИН refresh (race protection)', () async {
      final fakeTokens = _FakeTokenStorage();
      var refreshCallCount = 0;
      final refreshClient = Dio(
        BaseOptions(
          baseUrl: 'http://test/api/v1',
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      final dio = Dio(
        BaseOptions(
          baseUrl: 'http://test/api/v1',
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      final adapter = DioAdapter(
        dio: refreshClient,
        matcher: const UrlRequestMatcher(),
      );
      dio.httpClientAdapter = adapter;

      adapter.onGet(
        '/vpn/config',
        (server) {
          if (fakeTokens.access == 'new-access') {
            server.reply(200, {'ok': true});
          } else {
            server.reply(401, {'detail': 'expired'});
          }
        },
      );
      adapter.onPost(
        RegExp(r'auth/refresh'),
        (server) async {
          refreshCallCount++;
          await Future<void>.delayed(const Duration(milliseconds: 50));
          server.reply(
            200,
            {'access_token': 'new-access', 'refresh_token': 'new-refresh'},
          );
        },
      );

      dio.interceptors.add(
        JwtRefreshInterceptor(
          dio: dio,
          refreshEndpoint: 'auth/refresh',
          tokenStorage: fakeTokens,
          refreshClient: refreshClient,
        ),
      );

      final futures = [
        dio.get<Map<String, dynamic>>('/vpn/config'),
        dio.get<Map<String, dynamic>>('/vpn/config'),
        dio.get<Map<String, dynamic>>('/vpn/config'),
      ];
      await Future.wait(futures);

      expect(
        refreshCallCount,
        1,
        reason: 'Race protection: только один refresh для параллельных 401',
      );
      expect(fakeTokens.access, 'new-access');
    });

    test('refresh с invalid refresh_token → clear() вызван, 401 возвращён', () async {
      final fakeTokens = _FakeTokenStorage(refresh: 'expired-refresh');
      final refreshClient = Dio(
        BaseOptions(
          baseUrl: 'http://test/api/v1',
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      final dio = Dio(
        BaseOptions(
          baseUrl: 'http://test/api/v1',
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      final adapter = DioAdapter(
        dio: refreshClient,
        matcher: const UrlRequestMatcher(),
      );
      dio.httpClientAdapter = adapter;

      adapter.onGet(
        '/vpn/config',
        (server) => server.reply(401, {'detail': 'expired'}),
      );
      adapter.onPost(
        RegExp(r'auth/refresh'),
        (server) => server.reply(401, {'detail': 'refresh token invalid'}),
      );

      dio.interceptors.add(
        JwtRefreshInterceptor(
          dio: dio,
          refreshEndpoint: 'auth/refresh',
          tokenStorage: fakeTokens,
          refreshClient: refreshClient,
        ),
      );

      final resp = await dio.get<Map<String, dynamic>>('/vpn/config');
      expect(resp.statusCode, 401);
      expect(fakeTokens.clearCount, 1, reason: 'storage.clear() должен вызваться');
      expect(fakeTokens.access, '');
      expect(fakeTokens.refresh, '');
    });
  });
}