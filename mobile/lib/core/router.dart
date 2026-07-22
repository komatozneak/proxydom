import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/application/auth_provider.dart';
import '../features/auth/application/auth_state.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/verify_screen.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/settings/presentation/settings_screen.dart';

/// Роутер приложения.
///
/// Состояние авторизации читается из [authProvider] через Riverpod.
/// GoRouter получает сигнал о смене auth через [GoRouterRefreshNotifier]
/// (подписка настраивается в main.dart на [ProviderContainer]).
class AppRouter {
  AppRouter._();

  /// Телефон, введённый на LoginScreen и передаваемый на Verify через query.
  /// Хранится статикой до появления отдельного state (Шаг 19+).
  static String? pendingPhone;

  /// Глобальный listenable — связан с authProvider в main.dart.
  static final GoRouterRefreshNotifier refreshNotifier =
      GoRouterRefreshNotifier();

  static final GoRouter config = GoRouter(
    // Prefer /home: with tokens restored in main() before runApp, redirect
    // sends authed users straight home instead of flashing /login.
    initialLocation: '/home',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final auth = _readAuth(context);
      // Still loading / no ProviderScope — do not bounce to login.
      if (auth == null) return null;

      final loc = state.matchedLocation;
      final goingToLogin = loc == '/login';
      final goingToVerify = loc.startsWith('/verify');
      final goingToHome = loc == '/home';
      final goingToSettings = loc == '/settings';

      final isAuthed = auth is AuthStateAuthenticated;

      if (!isAuthed && (goingToLogin || goingToVerify)) {
        return null; // можно оставаться на login/verify
      }
      if (!isAuthed && !goingToLogin && !goingToVerify) {
        return '/login'; // back-button protection: не пускаем на /home
      }
      if (isAuthed && (goingToHome || goingToSettings)) {
        return null; // уже на home/settings
      }
      if (isAuthed && !goingToHome && !goingToSettings) {
        return '/home';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (c, s) => const LoginScreen()),
      GoRoute(
        path: '/verify',
        builder: (c, s) => VerifyScreen(
          phone: s.uri.queryParameters['phone'] ?? pendingPhone ?? '',
        ),
      ),
      GoRoute(path: '/home', builder: (c, s) => const HomeScreen()),
      GoRoute(path: '/settings', builder: (c, s) => const SettingsScreen()),
    ],
  );

  /// Достаёт AuthState через [ProviderScope.containerOf].
  ///
  /// Returns `null` while [authProvider] is still loading so redirect does not
  /// treat a cold start as logged-out.
  static AuthState? _readAuth(BuildContext context) {
    try {
      final container = ProviderScope.containerOf(context);
      final async = container.read(authProvider);
      if (async.isLoading && !async.hasValue) {
        return null;
      }
      if (async.hasError && !async.hasValue) {
        return const AuthStateUnauthenticated();
      }
      return async.valueOrNull ?? const AuthStateUnauthenticated();
    } catch (_) {
      return null;
    }
  }
}

/// Re-export для удобства импорта из других слоёв.
typedef AuthRouterListenable = GoRouterRefreshNotifier;
