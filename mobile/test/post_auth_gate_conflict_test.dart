import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:teremok_connect/core/theme.dart';
import 'package:teremok_connect/features/auth/application/auth_provider.dart';
import 'package:teremok_connect/features/auth/application/auth_state.dart';
import 'package:teremok_connect/features/beta/application/beta_providers.dart';
import 'package:teremok_connect/features/beta/data/beta_api.dart';
import 'package:teremok_connect/features/beta/data/beta_entitlement.dart';
import 'package:teremok_connect/features/beta/presentation/post_auth_gate_screen.dart';
import 'package:teremok_connect/l10n/app_localizations.dart';

class _AuthedNotifier extends AuthNotifier {
  @override
  Future<AuthState> build() async => const AuthStateAuthenticated(
        accessToken: 'test-access',
        refreshToken: 'test-refresh',
      );
}

class _FailingBetaApi extends BetaApi {
  @override
  Future<BetaEntitlement> fetchEntitlement() async {
    throw DioException(
      requestOptions: RequestOptions(path: '/beta/entitlement'),
      type: DioExceptionType.connectionError,
      message: 'failed host lookup',
    );
  }
}

Widget _gateApp(ProviderContainer container) {
  final router = GoRouter(
    initialLocation: '/gate',
    routes: [
      GoRoute(
        path: '/gate',
        builder: (_, __) => const PostAuthGateScreen(),
      ),
      GoRoute(path: '/login', builder: (_, __) => const SizedBox()),
      GoRoute(
        path: '/bootstrap-failed',
        builder: (_, __) => const SizedBox(),
      ),
      GoRoute(path: '/home', builder: (_, __) => const SizedBox()),
      GoRoute(path: '/promo', builder: (_, __) => const SizedBox()),
      GoRoute(path: '/locked', builder: (_, __) => const SizedBox()),
      GoRoute(path: '/onboarding', builder: (_, __) => const SizedBox()),
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

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(vpnChannel, null);
  });

  testWidgets(
      'gate shows VPN conflict UX when entitlement fails and foreign Always-on',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(vpnChannel, (call) async {
      if (call.method == 'getVpnConflict') {
        return <String, Object?>{
          'foreignAlwaysOn': true,
          'packageName': 'com.ogonconnect.app',
          'appLabel': 'Огонь',
          'lockdown': true,
        };
      }
      if (call.method == 'openVpnSettings') return true;
      return null;
    });

    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(_AuthedNotifier.new),
        betaApiProvider.overrideWithValue(_FailingBetaApi()),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authProvider.future);

    await tester.pumpWidget(_gateApp(container));
    await tester.pump();
    // 3 entitlement retries with 400ms / 800ms backoff.
    await tester.pump(const Duration(seconds: 3));

    expect(find.text('Мешает другой VPN'), findsOneWidget);
    expect(find.textContaining('Огонь'), findsOneWidget);
    expect(find.text('Открыть настройки VPN'), findsOneWidget);
    expect(find.text('Повторить'), findsOneWidget);
    expect(
      find.text('Не удалось проверить доступ. Проверьте связь.'),
      findsNothing,
    );
  });

  testWidgets(
      'gate shows VPN conflict UX when entitlement fails and live foreign VPN',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(vpnChannel, (call) async {
      if (call.method == 'getVpnConflict') {
        return <String, Object?>{
          'foreignAlwaysOn': false,
          'foreignVpnActive': true,
          'lockdown': false,
        };
      }
      if (call.method == 'openVpnSettings') return true;
      return null;
    });

    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(_AuthedNotifier.new),
        betaApiProvider.overrideWithValue(_FailingBetaApi()),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authProvider.future);

    await tester.pumpWidget(_gateApp(container));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    expect(find.text('Мешает другой VPN'), findsOneWidget);
    expect(find.text('Открыть настройки VPN'), findsOneWidget);
    expect(
      find.text('Не удалось проверить доступ. Проверьте связь.'),
      findsNothing,
    );
  });

  testWidgets(
      'gate shows betaGateError when entitlement fails without VPN conflict',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(vpnChannel, (call) async {
      if (call.method == 'getVpnConflict') {
        return <String, Object?>{
          'foreignAlwaysOn': false,
          'lockdown': false,
        };
      }
      return null;
    });

    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(_AuthedNotifier.new),
        betaApiProvider.overrideWithValue(_FailingBetaApi()),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authProvider.future);

    await tester.pumpWidget(_gateApp(container));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    expect(
      find.text('Не удалось проверить доступ. Проверьте связь.'),
      findsOneWidget,
    );
    expect(find.text('Открыть настройки VPN'), findsNothing);
    expect(find.text('Мешает другой VPN'), findsNothing);
  });
}
