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
import 'package:proxydom/features/vpn/data/vpn_controller.dart';
import 'package:proxydom/l10n/app_localizations.dart';

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
