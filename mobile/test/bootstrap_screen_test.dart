import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:teremok_connect/core/theme.dart';
import 'package:teremok_connect/features/auth/application/auth_provider.dart';
import 'package:teremok_connect/features/auth/application/auth_state.dart';
import 'package:teremok_connect/features/auth/presentation/bootstrap_failed_screen.dart';
import 'package:teremok_connect/features/auth/presentation/bootstrap_loading_screen.dart';
import 'package:teremok_connect/l10n/app_localizations.dart';

class _HangingAuth extends AuthNotifier {
  @override
  Future<AuthState> build() => Completer<AuthState>().future;
}

class _FailedAuth extends AuthNotifier {
  var retried = 0;

  @override
  Future<AuthState> build() async => const AuthStateBootstrapFailed();

  @override
  Future<void> retryBootstrap() async {
    retried += 1;
    state = const AsyncLoading();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    state = const AsyncData(AuthStateBootstrapFailed());
  }
}

class _AuthedAuth extends AuthNotifier {
  @override
  Future<AuthState> build() async => const AuthStateAuthenticated(
        accessToken: 'access',
        refreshToken: 'refresh',
      );
}

Widget _bootstrapApp(
  ProviderContainer container, {
  String location = '/bootstrap',
}) {
  final router = GoRouter(
    initialLocation: location,
    redirect: (context, state) {
      final async = container.read(authProvider);
      final loc = state.matchedLocation;
      if (async.isLoading && !async.hasValue) {
        return loc == '/bootstrap' ? null : '/bootstrap';
      }
      final auth = async.valueOrNull;
      if (auth is AuthStateBootstrapFailed) {
        return loc == '/bootstrap-failed' ? null : '/bootstrap-failed';
      }
      if (auth is AuthStateAuthenticated && loc == '/bootstrap') {
        return '/gate';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/bootstrap',
        builder: (_, __) => const BootstrapLoadingScreen(),
      ),
      GoRoute(
        path: '/bootstrap-failed',
        builder: (_, __) => const BootstrapFailedScreen(),
      ),
      GoRoute(
        path: '/gate',
        builder: (_, __) => const Scaffold(body: Text('gate')),
      ),
      GoRoute(
        path: '/restore',
        builder: (_, __) => const Scaffold(body: Text('restore')),
      ),
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

  testWidgets('loading auth shows bootstrap spinner instead of shell',
      (tester) async {
    final container = ProviderContainer(
      overrides: [authProvider.overrideWith(_HangingAuth.new)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_bootstrapApp(container));
    await tester.pump();

    expect(find.byKey(BootstrapLoadingScreen.progressKey), findsOneWidget);
    expect(find.text('Не удалось начать сессию. Проверьте связь.'), findsNothing);
  });

  testWidgets('bootstrap failure shows retry and retry re-enters loading',
      (tester) async {
    final auth = _FailedAuth();
    final container = ProviderContainer(
      overrides: [authProvider.overrideWith(() => auth)],
    );
    addTearDown(container.dispose);
    await container.read(authProvider.future);

    await tester.pumpWidget(
      _bootstrapApp(container, location: '/bootstrap-failed'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Не удалось начать сессию. Проверьте связь.'), findsOneWidget);
    expect(find.text('Повторить'), findsOneWidget);

    await tester.tap(find.text('Повторить'));
    await tester.pump();

    expect(auth.retried, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 30));
    await tester.pumpAndSettle();
    expect(find.text('Повторить'), findsOneWidget);
  });

  testWidgets('authenticated bootstrap leaves the spinner for the gate',
      (tester) async {
    final container = ProviderContainer(
      overrides: [authProvider.overrideWith(_AuthedAuth.new)],
    );
    addTearDown(container.dispose);
    await container.read(authProvider.future);

    await tester.pumpWidget(_bootstrapApp(container));
    await tester.pumpAndSettle();

    expect(find.text('gate'), findsOneWidget);
    expect(find.byKey(BootstrapLoadingScreen.progressKey), findsNothing);
  });
}
