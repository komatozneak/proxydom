import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/application/auth_provider.dart'
    show authProvider, GoRouterRefreshNotifier;
import '../features/auth/application/auth_state.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/verify_screen.dart';
import '../features/beta/presentation/post_auth_gate_screen.dart';
import '../features/beta/presentation/promo_code_screen.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/onboarding/data/onboarding_prefs.dart';
import '../features/onboarding/presentation/onboarding_screen.dart';
import '../features/onboarding/presentation/welcome_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/settings/presentation/split_tunnel_sites_screen.dart';
import '../features/shell/presentation/main_shell.dart';
import '../features/vpn/presentation/locations_screen.dart';

/// Роутер приложения.
///
/// Funnel: welcome? → login → verify → /gate → promo? → onboarding? → shell.
/// Shell: Locations | Home | Settings (StatefulShellRoute).
/// Состояние авторизации читается из [authProvider] через Riverpod.
class AppRouter {
  AppRouter._();

  /// Телефон, введённый на LoginScreen и передаваемый на Verify через query.
  static String? pendingPhone;

  /// Cached welcome flag so redirect stays sync (warmed in main / gate).
  static bool? welcomeSeenCache;

  /// After [PostAuthGateScreen] finishes once per auth session.
  /// Cold restore hits /home → redirect to /gate until this is true.
  static bool postAuthResolved = false;

  /// Глобальный listenable — связан с authProvider в main.dart.
  static final GoRouterRefreshNotifier refreshNotifier =
      GoRouterRefreshNotifier();

  static final GoRouter config = GoRouter(
    // Prefer /home: with tokens restored in main() before runApp, redirect
    // sends authed users through /gate instead of flashing /login.
    initialLocation: '/home',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final auth = _readAuth(context);
      // Still loading / no ProviderScope — do not bounce to login.
      if (auth == null) return null;

      final loc = state.matchedLocation;
      final goingToLogin = loc == '/login';
      final goingToVerify = loc.startsWith('/verify');
      final goingToWelcome = loc == '/welcome';
      final goingToGate = loc == '/gate';
      final goingToPromo = loc == '/promo';
      final goingToOnboarding = loc == '/onboarding';
      final inShell = loc == '/home' ||
          loc == '/locations' ||
          loc == '/settings' ||
          loc.startsWith('/settings/');

      final isAuthed = auth is AuthStateAuthenticated;

      if (!isAuthed) {
        postAuthResolved = false;
        if (goingToLogin || goingToVerify || goingToWelcome) {
          return null;
        }
        // First launch: optional welcome before login (does not affect restore).
        if (welcomeSeenCache == false) {
          return '/welcome';
        }
        return '/login';
      }

      // Authed: leave login/verify/welcome for the entitlement gate.
      if (goingToLogin || goingToVerify || goingToWelcome) {
        return '/gate';
      }
      if (goingToGate || goingToPromo || goingToOnboarding) {
        return null;
      }
      // Shell only after gate has resolved this session.
      if (inShell && !postAuthResolved) {
        return '/gate';
      }
      if (inShell) {
        return null;
      }
      return '/gate';
    },
    routes: [
      GoRoute(path: '/welcome', builder: (c, s) => const WelcomeScreen()),
      GoRoute(path: '/login', builder: (c, s) => const LoginScreen()),
      GoRoute(
        path: '/verify',
        builder: (c, s) => VerifyScreen(
          phone: s.uri.queryParameters['phone'] ?? pendingPhone ?? '',
        ),
      ),
      GoRoute(path: '/gate', builder: (c, s) => const PostAuthGateScreen()),
      GoRoute(path: '/promo', builder: (c, s) => const PromoCodeScreen()),
      GoRoute(
        path: '/onboarding',
        builder: (c, s) => const OnboardingScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return MainShell(navigationShell: navigationShell);
        },
        branches: [
          // Order matches bottom nav: Locations | Home | Settings.
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/locations',
                builder: (c, s) => const LocationsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                builder: (c, s) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (c, s) => const SettingsScreen(),
                routes: [
                  GoRoute(
                    path: 'split-tunnel',
                    builder: (c, s) => const SplitTunnelSitesScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );

  /// Warm [welcomeSeenCache] before first redirect (call from main).
  static Future<void> warmWelcomeFlag() async {
    welcomeSeenCache = await OnboardingPrefs.isWelcomeSeen();
  }

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
