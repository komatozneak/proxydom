import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/application/auth_provider.dart';
import '../features/auth/application/auth_state.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/verify_screen.dart';
import '../features/home/presentation/home_screen.dart';

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
    initialLocation: '/login',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final auth = _readAuth(context);
      // Пока AsyncNotifier не зарезолвился — пропускаем, первый build покажет loader.
      if (auth == null) return null;

      final loc = state.matchedLocation;
      final goingToLogin = loc == '/login';
      final goingToVerify = loc.startsWith('/verify');
      final goingToHome = loc == '/home';

      final isAuthed = auth is AuthStateAuthenticated;

      if (!isAuthed && (goingToLogin || goingToVerify)) {
        return null; // можно оставаться на login/verify
      }
      if (!isAuthed && !goingToLogin && !goingToVerify) {
        return '/login'; // back-button protection: не пускаем на /home
      }
      if (isAuthed && goingToHome) {
        return null; // уже на home
      }
      if (isAuthed && !goingToHome) {
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
    ],
  );

  /// Достаёт AuthState через [ProviderScope.containerOf]. В тестах без
  /// ProviderScope вернёт null — redirect пропустит (первый кадр).
  static AuthState? _readAuth(BuildContext context) {
    try {
      final container = ProviderScope.containerOf(context);
      final auth = container.read(authProvider).valueOrNull;
      return auth ?? const AuthStateUnknown();
    } catch (_) {
      return null;
    }
  }
}

/// Re-export для удобства импорта из других слоёв.
typedef AuthRouterListenable = GoRouterRefreshNotifier;