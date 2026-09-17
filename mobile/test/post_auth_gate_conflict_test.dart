import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teremok_connect/core/config.dart';
import 'package:teremok_connect/core/theme.dart';
import 'package:teremok_connect/features/auth/application/auth_provider.dart';
import 'package:teremok_connect/features/auth/application/auth_state.dart';
import 'package:teremok_connect/features/auth/application/logout_handler.dart';
import 'package:teremok_connect/features/auth/data/recovery_code_storage.dart';
import 'package:teremok_connect/features/beta/application/beta_providers.dart';
import 'package:teremok_connect/features/beta/data/beta_api.dart';
import 'package:teremok_connect/features/beta/data/beta_entitlement.dart';
import 'package:teremok_connect/features/beta/presentation/post_auth_gate_screen.dart';
import 'package:teremok_connect/features/onboarding/data/onboarding_prefs.dart';
import 'package:teremok_connect/l10n/app_localizations.dart';

import 'helpers/secure_storage_mock.dart';

class _AuthedNotifier extends AuthNotifier {
  @override
  Future<AuthState> build() async => const AuthStateAuthenticated(
        accessToken: 'test-access',
        refreshToken: 'test-refresh',
      );
}

class _CountingBetaApi extends BetaApi {
  _CountingBetaApi({
    required this.results,
  });

  final List<Object> results;
  int calls = 0;

  @override
  Future<BetaEntitlement> fetchEntitlement() async {
    calls += 1;
    final i = calls - 1;
    final item = i < results.length ? results[i] : results.last;
    if (item is BetaEntitlement) return item;
    if (item is Exception) throw item;
    throw StateError('unexpected mock result $item');
  }
}

const _okEntitlement = BetaEntitlement(
  hasAccess: true,
  betaPromoGateEnabled: false,
  authAnonymousEnabled: true,
);

DioException _connErr() => DioException(
      requestOptions: RequestOptions(path: '/beta/entitlement'),
      type: DioExceptionType.connectionError,
      message: 'failed host lookup',
    );

DioException _unauthorized() => DioException(
      requestOptions: RequestOptions(path: '/beta/entitlement'),
      response: Response(
        requestOptions: RequestOptions(path: '/beta/entitlement'),
        statusCode: 401,
      ),
      type: DioExceptionType.badResponse,
      message: 'unauthorized',
    );

Widget _gateApp(ProviderContainer container) {
  final router = GoRouter(
    initialLocation: '/gate',
    routes: [
      GoRoute(
        path: '/gate',
        builder: (_, __) => const PostAuthGateScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (_, __) => const Text('LOGIN'),
      ),
      GoRoute(
        path: '/bootstrap-failed',
        builder: (_, __) => const SizedBox(),
      ),
      GoRoute(
        path: '/home',
        builder: (_, __) => const Text('HOME'),
      ),
      GoRoute(path: '/promo', builder: (_, __) => const SizedBox()),
      GoRoute(path: '/locked', builder: (_, __) => const SizedBox()),
      GoRoute(path: '/onboarding', builder: (_, __) => const SizedBox()),
      GoRoute(path: '/recovery', builder: (_, __) => const SizedBox()),
    ],
  );

  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      theme: AppTheme.light,
      locale: const Locale('ru'),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      routerConfig: router,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const vpnChannel = MethodChannel('teremok/vpn');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    mockSecureStorage();
    await OnboardingPrefs.markCompleted(userId: 'unknown');
    await RecoveryCodeStorage.instance.markShown();
  });

  void mockVpn({
    String status = 'idle',
    bool hasSession = false,
    Map<String, Object?>? conflict,
    List<String>? stopLog,
  }) {
    messenger.setMockMethodCallHandler(vpnChannel, (call) async {
      switch (call.method) {
        case 'getVpnConflict':
          return conflict ??
              <String, Object?>{
                'foreignAlwaysOn': false,
                'lockdown': false,
              };
        case 'getStatus':
          return status;
        case 'hasActiveSession':
          return hasSession;
        case 'stop':
        case 'wipeSession':
          stopLog?.add(call.method);
          // After stop, treat tunnel as idle for follow-up resolve.
          status = 'idle';
          hasSession = false;
          return true;
        case 'openVpnSettings':
          return true;
        default:
          return null;
      }
    });
  }

  tearDown(() {
    messenger.setMockMethodCallHandler(vpnChannel, null);
  });

  testWidgets(
      'gate shows VPN conflict UX when entitlement fails and foreign Always-on',
      (tester) async {
    mockVpn(
      conflict: {
        'foreignAlwaysOn': true,
        'packageName': 'com.ogonconnect.app',
        'appLabel': 'Огонь',
        'lockdown': true,
      },
    );

    final api = _CountingBetaApi(results: [_connErr()]);
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(_AuthedNotifier.new),
        betaApiProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authProvider.future);

    await tester.pumpWidget(_gateApp(container));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('Мешает другой VPN'), findsOneWidget);
    expect(find.textContaining('Огонь'), findsOneWidget);
    expect(find.text('Открыть настройки VPN'), findsOneWidget);
    expect(find.text('Повторить'), findsOneWidget);
  });

  testWidgets(
      'gate shows VPN conflict UX when entitlement fails and live foreign VPN',
      (tester) async {
    mockVpn(
      conflict: {
        'foreignAlwaysOn': false,
        'foreignVpnActive': true,
        'lockdown': false,
      },
    );

    final api = _CountingBetaApi(results: [_connErr()]);
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(_AuthedNotifier.new),
        betaApiProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authProvider.future);

    await tester.pumpWidget(_gateApp(container));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('Мешает другой VPN'), findsOneWidget);
    expect(find.text('Открыть настройки VPN'), findsOneWidget);
  });

  testWidgets(
      'gate shows network error when entitlement fails without VPN conflict',
      (tester) async {
    mockVpn();

    final api = _CountingBetaApi(results: [_connErr()]);
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(_AuthedNotifier.new),
        betaApiProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authProvider.future);

    await tester.pumpWidget(_gateApp(container));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('Нет связи с сервером. Попробуйте снова.'), findsOneWidget);
    expect(find.byKey(kGateDisconnectVpnKey), findsOneWidget);
    expect(find.text('Мешает другой VPN'), findsNothing);
  });

  testWidgets('retry after error calls entitlement again', (tester) async {
    mockVpn();
    final api = _CountingBetaApi(results: [_connErr(), _connErr(), _okEntitlement]);
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(_AuthedNotifier.new),
        betaApiProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authProvider.future);

    await tester.pumpWidget(_gateApp(container));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(kGateRetryKey), findsOneWidget);
    final callsAfterFail = api.calls;
    expect(callsAfterFail, greaterThanOrEqualTo(1));

    await tester.tap(find.byKey(kGateRetryKey));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(api.calls, greaterThan(callsAfterFail));
  });

  testWidgets('own VPN up stops tunnel then reaches home', (tester) async {
    final stops = <String>[];
    mockVpn(status: 'connected', hasSession: true, stopLog: stops);

    // Parallel leftover stop + two short fails, then post-stop resolve OK.
    final api = _CountingBetaApi(
      results: [_connErr(), _connErr(), _okEntitlement],
    );
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(_AuthedNotifier.new),
        betaApiProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authProvider.future);

    await tester.pumpWidget(_gateApp(container));
    await tester.pump();
    // House loading UI (not bare white spinner) while resolving.
    expect(find.text('Проверяем доступ…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(stops, contains('stop'), reason: 'api.calls=${api.calls}');
    expect(api.calls, greaterThanOrEqualTo(3));
    expect(
      find.text('HOME'),
      findsOneWidget,
      reason:
          'error=${find.text('Нет связи с сервером. Попробуйте снова').evaluate().length} '
          'checking=${find.text('Проверяем доступ…').evaluate().length} '
          'onboarding=${find.textContaining('Далее').evaluate().length}',
    );
  });

  testWidgets('leftover VPN stop runs before entitlement hang finishes',
      (tester) async {
    final stops = <String>[];
    mockVpn(status: 'connected', hasSession: true, stopLog: stops);

    final api = _HangThenOkBetaApi();
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(_AuthedNotifier.new),
        betaApiProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authProvider.future);

    await tester.pumpWidget(_gateApp(container));
    await tester.pump();
    await api.firstFetchStarted.future;
    // Parallel stop must fire without waiting full hang.
    await tester.pump(const Duration(milliseconds: 50));
    expect(stops, contains('stop'));
    expect(kGateEntitlementTimeout, const Duration(seconds: 2));

    // Let gate timeouts + post-stop resolve complete.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('401 on gate re-resolves without stuck white loader',
      (tester) async {
    mockVpn();
    var bootstrapCalls = 0;
    var logoutCalls = 0;

    final api = _CountingBetaApi(results: [_unauthorized(), _okEntitlement]);

    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(() => _401AuthedNotifier(() {
              bootstrapCalls += 1;
            })),
        betaApiProvider.overrideWithValue(api),
        logoutHandlerProvider.overrideWith((ref) {
          return _RecordingLogoutHandler(ref, () {
            logoutCalls += 1;
          });
        }),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authProvider.future);

    await tester.pumpWidget(_gateApp(container));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    // CI runs `--dart-define=AUTH_ANONYMOUS=false` (phone path → logout).
    // Local / TF product default is anonymous → retryBootstrap + re-resolve.
    expect(find.byType(CircularProgressIndicator), findsNothing);
    if (AppConfig.authAnonymous) {
      expect(bootstrapCalls, 1);
      expect(api.calls, greaterThanOrEqualTo(2));
      expect(find.text('HOME'), findsOneWidget);
    } else {
      expect(bootstrapCalls, 0);
      expect(logoutCalls, 1);
      expect(find.text('LOGIN'), findsOneWidget);
    }
  });
}

class _HangThenOkBetaApi extends BetaApi {
  final Completer<void> firstFetchStarted = Completer<void>();
  int calls = 0;

  @override
  Future<BetaEntitlement> fetchEntitlement() async {
    calls += 1;
    if (calls == 1) {
      if (!firstFetchStarted.isCompleted) firstFetchStarted.complete();
      // Never completes — gate .timeout cancels the wait without a pending Timer.
      return Completer<BetaEntitlement>().future;
    }
    return _okEntitlement;
  }
}

class _RecordingLogoutHandler extends LogoutHandler {
  _RecordingLogoutHandler(super.ref, this.onLogout);

  final VoidCallback onLogout;

  @override
  Future<LogoutResult> logout({bool autoRegister = false}) async {
    onLogout();
    return const LogoutSuccess();
  }
}

class _401AuthedNotifier extends AuthNotifier {
  _401AuthedNotifier(this.onRetryBootstrap);

  final VoidCallback onRetryBootstrap;

  @override
  Future<AuthState> build() async => const AuthStateAuthenticated(
        accessToken: 'test-access',
        refreshToken: 'test-refresh',
      );

  @override
  Future<void> retryBootstrap() async {
    onRetryBootstrap();
    state = const AsyncData(
      AuthStateAuthenticated(
        accessToken: 'test-access-2',
        refreshToken: 'test-refresh-2',
      ),
    );
  }
}
