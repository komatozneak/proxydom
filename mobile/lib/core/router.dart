import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'diagnostics/ui_log.dart';

import '../features/home/presentation/home_screen.dart';
import '../features/onboarding/data/onboarding_prefs.dart';
import '../features/onboarding/presentation/onboarding_screen.dart';
import '../features/settings/presentation/no_vpn_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/settings/presentation/tunnel_log_screen.dart';
import '../features/shell/presentation/main_shell.dart';
import '../features/vpn/presentation/hy2_import_screen.dart';
import '../features/vpn/presentation/locations_screen.dart';
import '../features/vpn/presentation/share_qr_scan_screen.dart';

/// Local configurator routes: onboarding, then Home / servers / settings.
class AppRouter {
  AppRouter._();

  /// Cached welcome flag so redirect stays sync (warmed in main).
  static bool? welcomeSeenCache;

  /// Root navigator — import and scan sit above the shell.
  static final GlobalKey<NavigatorState> rootNavigatorKey =
      GlobalKey<NavigatorState>(debugLabel: 'root');

  static final GoRouter config = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/home',
    observers: [UiNavObserver()],
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final goingToOnboarding = loc == '/onboarding';
      final inShell = loc == '/home' ||
          loc == '/locations' ||
          loc == '/settings' ||
          loc.startsWith('/settings/');
      final goingToImport = loc == '/import';
      final goingToScan = loc == '/scan';
      final introDone = welcomeSeenCache == true;
      final String? next;
      if (!introDone && !goingToOnboarding) {
        next = '/onboarding';
      } else if (inShell || goingToImport || goingToOnboarding || goingToScan) {
        next = null;
      } else {
        next = '/home';
      }
      if (next != null && next != loc) {
        UiLog.action(
          'router',
          'redirect',
          extra: {'from': loc, 'to': next},
        );
      }
      return next;
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (c, s) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/import',
        parentNavigatorKey: rootNavigatorKey,
        builder: (c, s) => const Hy2ImportScreen(),
      ),
      GoRoute(
        path: '/scan',
        parentNavigatorKey: rootNavigatorKey,
        builder: (c, s) => const ShareQrScanScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return MainShell(navigationShell: navigationShell);
        },
        branches: [
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
                    path: 'logs',
                    builder: (context, state) => const TunnelLogScreen(),
                  ),
                  GoRoute(
                    path: 'no-vpn',
                    builder: (c, s) => const NoVpnScreen(),
                  ),
                  GoRoute(
                    path: 'split-tunnel',
                    redirect: (c, s) => '/settings/no-vpn',
                  ),
                  GoRoute(
                    path: 'modes',
                    redirect: (c, s) => '/settings/no-vpn',
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
}

/// Kept so older tests can notify a router refresh without an account.
class GoRouterRefreshNotifier extends ChangeNotifier {
  void notifyAuthChanged() => notifyListeners();
}
