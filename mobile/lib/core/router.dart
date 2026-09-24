import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/application/auth_provider.dart'
    show authProvider, GoRouterRefreshNotifier;
import '../features/auth/application/auth_state.dart';
import '../features/auth/presentation/bootstrap_failed_screen.dart';
import '../features/auth/presentation/bootstrap_loading_screen.dart';
import '../features/beta/presentation/post_auth_gate_screen.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/onboarding/data/onboarding_prefs.dart';
import '../features/onboarding/presentation/onboarding_screen.dart';
import '../features/onboarding/presentation/welcome_screen.dart';
import '../features/settings/presentation/no_vpn_screen.dart';
import '../features/settings/presentation/tunnel_log_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/shell/presentation/main_shell.dart';
import '../features/vpn/presentation/hy2_import_screen.dart';
import '../features/vpn/presentation/share_qr_scan_screen.dart';
import '../features/vpn/presentation/locations_screen.dart';
import 'config.dart';
import 'ios_store_gates.dart';

/// Роутер приложения.
///
/// Funnel (anonymous): bootstrap → /home (JWT) → soft entitlement in shell;
/// /gate only for promo / locked / restore / manual retry.
class AppRouter {
  AppRouter._();

  /// Cached welcome flag so redirect stays sync (warmed in main / gate).
  static bool? welcomeSeenCache;

  /// After JWT cold start, [PostAuthGateScreen], or promo redeem grants shell.
  /// Cold restore with JWT sets this true immediately so /home is not blocked
  /// by full-screen /gate (entitlement runs in background).
  /// MUST stay false while on /promo — never set true before destination is known.
  static bool postAuthResolved = false;

  /// JWT present → allow shell without waiting for entitlement.
  ///
  /// Used by redirect on cold bootstrap so Packet Tunnel stays up and Home
  /// paints immediately. Entitlement soft-check runs in [MainShell].
  @visibleForTesting
  static String enterShellForAuthedColdStart() {
    postAuthResolved = true;
    return '/home';
  }

  /// Soften recovery UX: one-shot code after register; Settings can recover.
  static String? pendingRecoveryCode;

  /// After entitlement unlock, open [destination]. Free clients never show a
  /// recovery-code cashier.
  static Future<void> goAfterEntitlement(
    BuildContext context,
    String destination,
  ) async {
    if (!context.mounted) return;
    postAuthResolved = true;
    context.go(destination);
  }

  /// Глобальный listenable — связан с authProvider в main.dart.
  static final GoRouterRefreshNotifier refreshNotifier =
      GoRouterRefreshNotifier();

  /// Root navigator — billing routes sit above [StatefulShellRoute].
  static final GlobalKey<NavigatorState> rootNavigatorKey =
      GlobalKey<NavigatorState>(debugLabel: 'root');

  static final GoRouter config = GoRouter(
    navigatorKey: rootNavigatorKey,
    // First frame is /bootstrap so cold register never blocks runApp.
    // Authed JWT → Home immediately; entitlement soft-check in shell.
    initialLocation: '/bootstrap',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final auth = _readAuth(context);
      final loc = state.matchedLocation;
      final goingToWelcome = loc == '/welcome';
      final goingToGate = loc == '/gate';
      final goingToPromo = loc == '/promo';
      final goingToLocked = loc == '/locked';
      final goingToRecovery = loc == '/recovery';
      final goingToRestore = loc == '/restore';
      final goingToBootstrap = loc == '/bootstrap';
      final goingToBootstrapFail = loc == '/bootstrap-failed';
      final goingToOnboarding = loc == '/onboarding';
      final inShell = loc == '/home' ||
          loc == '/locations' ||
          loc == '/settings' ||
          loc.startsWith('/settings/');
      // /subscription + /premium parked outside shell — still require auth gate.
      final goingToBillingTabs = loc == '/subscription' || loc == '/premium';
      final goingToImport = loc == '/import';
      final goingToScan = loc == '/scan';

      // Still loading / no ProviderScope — keep the bootstrap spinner on screen.
      // Free clients open Home without an account (ADR 026).
      if (freeKeyClient) {
        final introDone = welcomeSeenCache == true;
        if (!introDone && !goingToOnboarding) {
          return '/onboarding';
        }
        if (goingToBootstrap ||
            goingToBootstrapFail ||
            goingToWelcome ||
            goingToGate ||
            iosFreeClientRouteBlocked(loc)) {
          return '/home';
        }
        if (inShell || goingToImport || goingToOnboarding || goingToScan) {
          return null;
        }
        return '/home';
      }

      if (auth == null) {
        if (goingToBootstrap) return null;
        return '/bootstrap';
      }

      if (auth is AuthStateBootstrapFailed) {
        if (goingToBootstrapFail || goingToRestore) return null;
        return '/bootstrap-failed';
      }

      final isAuthed = auth is AuthStateAuthenticated;

      if (goingToBootstrap) {
        if (isAuthed) return enterShellForAuthedColdStart();
        if (auth is AuthStateUnauthenticated) {
          return AppConfig.authAnonymous ? '/welcome' : '/bootstrap-failed';
        }
        return null;
      }

      if (!isAuthed) {
        postAuthResolved = false;
        if (AppConfig.authAnonymous) {
          // Register runs in AuthNotifier on cold start (AsyncLoading → no
          // redirect). Reaching here unauthenticated means logout / expired
          // session — offer Welcome (new account vs restore) instead of
          // silently minting a fresh identity.
          if (goingToWelcome || goingToRestore || goingToBootstrapFail) {
            return null;
          }
          if (auth is AuthStateUnauthenticated) {
            return '/welcome';
          }
          return null;
        }
        // First launch: optional welcome before login.
        if (welcomeSeenCache == false) {
          return '/welcome';
        }
        return '/bootstrap-failed';
      }

      // Authed: leave welcome / bootstrap-fail for Home (soft entitlement later).
      if (goingToWelcome || goingToBootstrapFail) {
        return enterShellForAuthedColdStart();
      }
      if (iosFreeClientRouteBlocked(loc)) {
        return '/home';
      }
      if (goingToGate ||
          goingToPromo ||
          goingToLocked ||
          goingToRecovery ||
          goingToRestore) {
        return null;
      }
      // Onboarding + shell after cold-start flag or explicit gate resolution.
      // Do NOT allow /onboarding without postAuthResolved — that skipped promo.
      if ((goingToOnboarding ||
              inShell ||
              goingToBillingTabs ||
              goingToImport) &&
          !postAuthResolved) {
        return '/gate';
      }
      if (goingToOnboarding || inShell || goingToBillingTabs || goingToImport) {
        return null;
      }
      return enterShellForAuthedColdStart();
    },
    routes: [
      GoRoute(
        path: '/bootstrap',
        builder: (c, s) => const BootstrapLoadingScreen(),
      ),
      GoRoute(path: '/welcome', builder: (c, s) => const WelcomeScreen()),
      GoRoute(path: '/gate', builder: (c, s) => const PostAuthGateScreen()),
      GoRoute(
        path: '/bootstrap-failed',
        builder: (c, s) => const BootstrapFailedScreen(),
      ),
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
          // Locations | Home (center) | Settings
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
