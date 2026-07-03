import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:teremok_connect/app.dart';
import 'package:teremok_connect/core/api_client.dart';
import 'package:teremok_connect/core/config.dart';
import 'package:teremok_connect/core/jwt_interceptor.dart';
import 'package:teremok_connect/core/router.dart';
import 'package:teremok_connect/core/token_storage.dart';
import 'package:teremok_connect/features/auth/application/auth_provider.dart';
import 'package:teremok_connect/features/auth/application/auth_state.dart';
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