import 'package:go_router/go_router.dart';

import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/verify_screen.dart';
import '../features/home/presentation/home_screen.dart';

class AppRouter {
  AppRouter._();

  static bool _isAuthenticated = false;
  static String? _pendingPhone;

  static bool get isAuthenticated => _isAuthenticated;
  static String? get pendingPhone => _pendingPhone;

  static final GoRouter config = GoRouter(
    initialLocation: _isAuthenticated ? '/home' : '/login',
    redirect: (context, state) {
      final loggedIn = _isAuthenticated;
      final loc = state.matchedLocation;
      final goingToLogin = loc == '/login';
      final goingToVerify = loc.startsWith('/verify');

      if (!loggedIn && !goingToLogin && !goingToVerify) {
        return '/login';
      }
      if (loggedIn && (goingToLogin || goingToVerify)) {
        return '/home';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (c, s) => const LoginScreen()),
      GoRoute(
        path: '/verify',
        builder: (c, s) => VerifyScreen(
          phone: s.uri.queryParameters['phone'] ?? '',
        ),
      ),
      GoRoute(path: '/home', builder: (c, s) => const HomeScreen()),
    ],
  );

  static void setAuthenticated(bool value) => _isAuthenticated = value;
  static void setPendingPhone(String? phone) => _pendingPhone = phone;
}