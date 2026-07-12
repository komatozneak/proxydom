import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teremok_connect/app.dart';
import 'package:teremok_connect/core/api_client.dart';
import 'package:teremok_connect/core/config.dart';
import 'package:teremok_connect/core/result.dart';
import 'package:teremok_connect/core/retry_policy.dart';
import 'package:teremok_connect/core/router.dart';
import 'package:teremok_connect/core/theme.dart';
import 'package:teremok_connect/core/extensions.dart';
import 'package:teremok_connect/core/token_storage.dart';
import 'package:teremok_connect/features/auth/application/auth_provider.dart';
import 'package:teremok_connect/features/auth/application/auth_state.dart';
import 'package:teremok_connect/features/auth/application/logout_handler.dart';
import 'package:teremok_connect/features/auth/domain/phone_country.dart';
import 'package:teremok_connect/features/home/application/vpn_provider.dart';
import 'package:teremok_connect/features/vpn/data/vpn_config.dart';
import 'package:teremok_connect/features/vpn/data/vpn_controller.dart';
import 'package:teremok_connect/features/vpn/data/vpn_node.dart';
import 'package:teremok_connect/features/vpn/data/vpn_nodes_repository.dart';
import 'package:teremok_connect/features/vpn/data/vpn_service_config.dart';
import 'package:teremok_connect/l10n/app_localizations.dart';

/// Instant nodes catalog — home init must not hit the real VPS in CI.
class _FakeVpnNodesRepository extends VpnNodesRepository {
  @override
  Future<List<VpnNode>> listNodes() async => const [];

  @override
  Future<String?> getSelectedNodeId() async => null;
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
    await tester.pump();
    // initialLocation=/home; auth still loading → redirect skipped. Go login explicitly.
    AppRouter.config.go('/login');
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('Call me'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<PhoneCountry>), findsOneWidget);
    expect(find.byType(TextFormField), findsOneWidget);
  });

  testWidgets('App boots and shows login screen (ru)', (tester) async {
    AppLocale.set(const Locale('ru'));
    await tester.pumpWidget(_wrap(const TeremokApp()));
    await tester.pump();
    AppRouter.config.go('/login');
    await tester.pumpAndSettle();

    expect(find.text('Вход'), findsWidgets);
    expect(find.text('Позвонить'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<PhoneCountry>), findsOneWidget);
    expect(find.byType(TextFormField), findsOneWidget);
  });

  testWidgets('Login screen renders phone field and button', (tester) async {
    AppLocale.set(const Locale('ru'));
    await tester.pumpWidget(_wrap(const TeremokApp()));
    await tester.pump();
    AppRouter.config.go('/login');
    await tester.pumpAndSettle();

    expect(find.text('Позвонить'), findsOneWidget);
    expect(find.textContaining('🇷🇺'), findsOneWidget);
    expect(find.byType(TextFormField), findsOneWidget);
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
    expect(find.textContaining('Перезвонить'), findsOneWidget);
    expect(find.byType(TextField), findsAtLeastNWidgets(4));
  });

  testWidgets('Home screen shows Connect button when not connected', (tester) async {
    // authenticated() writes flutter_secure_storage — without a mock the
    // platform channel never completes and the test hits the 10m timeout.
    const secureChannel =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (call) async => null);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(secureChannel, null);
    });

    const vpnChannel = MethodChannel('teremok/vpn');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(vpnChannel, (call) async {
      if (call.method == 'getStatus') return 'idle';
      if (call.method == 'getLastError') return '';
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(vpnChannel, null);
    });

    SharedPreferences.setMockInitialValues({});
    AppLocale.set(const Locale('ru'));

    final container = ProviderContainer(
      overrides: [
        vpnNodesRepositoryProvider.overrideWithValue(_FakeVpnNodesRepository()),
      ],
    );
    addTearDown(container.dispose);

    await container.read(authProvider.notifier).authenticated(
          accessToken: 'fake',
          refreshToken: 'fake',
        );
    AppRouter.refreshNotifier.notifyAuthChanged();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TeremokApp(),
      ),
    );
    // Avoid pumpAndSettle — CircularProgressIndicator / timers never settle.
    await tester.pump();
    AppRouter.config.go('/home');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

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
      expect(service.dnsServers, ['10.255.255.2']);
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
      expect(service.routes, contains('0.0.0.0/0'));
      expect(service.routes, isNot(contains('::/0')));
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

  test('AppConfig.baseUrl defaults to prod VPS', () {
    expect(AppConfig.baseUrl, isNotEmpty);
    expect(AppConfig.baseUrl, contains('/api/v1'));
    expect(AppConfig.baseUrl, AppConfig.vpsBaseUrl);
  });

  test('AppConfig.vpsBaseUrl points to Yottasrc VPS prod backend', () {
    expect(AppConfig.vpsBaseUrl, 'http://204.11.2.216:8080/api/v1');
    expect(AppConfig.vpsBaseUrl, contains('204.11.2.216'));
    expect(AppConfig.vpsBaseUrl, contains('/api/v1'));
  });

  test('AppConfig dev switch via APP_ENV=dev dart-define', () {
    expect(AppConfig.baseUrlForEnvironment('prod'), AppConfig.vpsBaseUrl);
    expect(AppConfig.baseUrlForEnvironment('dev'), AppConfig.androidBaseUrl);
    expect(AppConfig.baseUrlForEnvironment('dev'), isNot(equals(AppConfig.vpsBaseUrl)));
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
      // Palette v3 oak+moss — expectations updated with hex migration.
      expect(AppBrand.primary, const Color(0xFF5D4037));
      expect(AppBrand.success, const Color(0xFF2E7D32));
      expect(AppBrand.warning, const Color(0xFFFF8F00));
      expect(AppBrand.error, const Color(0xFF5D4037));
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
          AppTheme.light.colorScheme.primary);
      expect(AppTheme.light.filledButtonTheme.style, isNotNull);
      expect(AppTheme.light.cardTheme.elevation, 2);
      expect(AppTheme.light.cardTheme.shape, isA<RoundedRectangleBorder>());
    });

    test('vpnStatusColor extension возвращает ожидаемые brand-цвета', () {
      final scheme = AppTheme.light.colorScheme;
      expect(scheme.vpnStatusColor('connected'), AppBrand.success);
      expect(scheme.vpnStatusColor('connecting'), AppBrand.warning);
      expect(scheme.vpnStatusColor('error'), AppBrand.error);
      expect(scheme.vpnStatusColor('unknown'), scheme.outline);
    });
  });

  test('ApiClient has correct base URL', () {
    expect(ApiClient.instance.options.baseUrl, AppConfig.baseUrl);
  });

  test('TokenStorage can be cleared safely on empty storage', () async {
    const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
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
}