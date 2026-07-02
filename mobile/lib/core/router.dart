import 'package:go_router/go_router.dart';

import '../features/auth/presentation/login_screen.dart';
import '../features/home/presentation/home_screen.dart';

class AppRouter {
  AppRouter._();

  // Ключ для аутентификации потом будем менять на Riverpod authState
  // На этом шаге просто хардкодим что юзер не залогинен
  static bool _isAuthenticated = false;

  static final GoRouter config = GoRouter(
    initialLocation: _isAuthenticated ? '/home' : '/login',
    redirect: (context, state) {
      final loggedIn = _isAuthenticated;
      final goingToLogin = state.matchedLocation == '/login';

      if (!loggedIn && !goingToLogin) return '/login';
      if (loggedIn && goingToLogin) return '/home';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => const HomeScreen(),
      ),
    ],
  );

  /// Временный setter чтобы LoginScreen мог переключать маршрут.
  /// В Шаге 8 заменим на Riverpod.
  static void setAuthenticated(bool value) => _isAuthenticated = value;
}
