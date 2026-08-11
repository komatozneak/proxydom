import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/account/presentation/account_hub_screen.dart';
import '../features/account/presentation/account_promo_screen.dart';
import '../features/account/presentation/email_link_screen.dart';
import '../features/account/presentation/telegram_link_screen.dart';
import '../features/auth/application/auth_provider.dart'
    show authProvider, GoRouterRefreshNotifier;
import '../features/auth/application/auth_state.dart';
import '../features/auth/data/recovery_code_storage.dart';
import '../features/auth/presentation/bootstrap_failed_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/recovery_code_screen.dart';
import '../features/auth/presentation/restore_access_screen.dart';
import '../features/auth/presentation/verify_screen.dart';
import '../features/beta/presentation/locked_access_screen.dart';
import '../features/beta/presentation/post_auth_gate_screen.dart';
import '../features/beta/presentation/promo_code_screen.dart';
import '../features/billing/presentation/premium_tab_screen.dart';
import '../features/billing/presentation/subscription_tab_screen.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/onboarding/data/onboarding_prefs.dart';
import '../features/onboarding/presentation/onboarding_screen.dart';
import '../features/onboarding/presentation/welcome_screen.dart';
import '../features/settings/presentation/devices_screen.dart';
import '../features/settings/presentation/no_vpn_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/shell/presentation/main_shell.dart';
import '../features/vpn/presentation/locations_screen.dart';
import 'config.dart';

/// Роутер приложения.
///
/// Funnel (phone): welcome? → login → verify → /gate → promo? → onboarding? → shell.
/// Funnel (anonymous): bootstrap → /gate → locked? → recovery? → onboarding? → shell.
class AppRouter {
  AppRouter._();

  /// Телефон, введённый на LoginScreen и передаваемый на Verify через query.
  static String? pendingPhone;

  /// Cached welcome flag so redirect stays sync (warmed in main / gate).
  static bool? welcomeSeenCache;

  /// After [PostAuthGateScreen] (or promo redeem) grants shell/onboarding.
  /// Cold restore hits /home → redirect to /gate until this is true.
  /// MUST stay false while on /promo — never set true before destination is known.
  static bool postAuthResolved = false;

  /// Soften recovery UX: one-shot code after register; Settings can recover.
  static String? pendingRecoveryCode;

  /// After entitlement unlock: show one-shot recovery screen if needed.
  ///
  /// Keeps [postAuthResolved] false until [RecoveryCodeScreen] confirms; otherwise
  /// sets it true and navigates to [destination] (`/home` or `/onboarding`).
  static Future<void> goAfterEntitlement(
    BuildContext context,
    String destination,
  ) async {
    var code = pendingRecoveryCode?.trim();
    if (code == null || code.isEmpty) {
      final shown = await RecoveryCodeStorage.instance.wasShown();
      if (!shown) {
        final archived = await RecoveryCodeStorage.instance.readArchived();
        final trimmed = archived?.trim();
        if (trimmed != null && trimmed.isNotEmpty) {
          code = trimmed;
          pendingRecoveryCode = trimmed;
        }
      }
    }
    if (!context.mounted) return;
    if (code != null && code.isNotEmpty) {
      postAuthResolved = false;
      context.go('/recovery');
      return;
    }
    postAuthResolved = true;
    context.go(destination);
  }

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
      final goingToLocked = loc == '/locked';
      final goingToRecovery = loc == '/recovery';
      final goingToRestore = loc == '/restore';
      final goingToBootstrapFail = loc == '/bootstrap-failed';
      final goingToOnboarding = loc == '/onboarding';
      final inShell = loc == '/home' ||
          loc == '/locations' ||
          loc == '/settings' ||
          loc.startsWith('/settings/');
      // /subscription + /premium parked outside shell — still require auth gate.
      final goingToBillingTabs = loc == '/subscription' || loc == '/premium';

      if (auth is AuthStateBootstrapFailed) {
        if (goingToBootstrapFail || goingToRestore) return null;
        return '/bootstrap-failed';
      }

      final isAuthed = auth is AuthStateAuthenticated;

      if (!isAuthed) {
        postAuthResolved = false;
        if (AppConfig.authAnonymous) {
          // Register runs in AuthNotifier; allow restore while waiting / failed.
          if (goingToWelcome || goingToRestore || goingToBootstrapFail) {
            return null;
          }
          return null;
        }
        if (goingToLogin || goingToVerify || goingToWelcome) {
          return null;
        }
        // First launch: optional welcome before login.
        if (welcomeSeenCache == false) {
          return '/welcome';
        }
        return '/login';
      }

      // Authed: leave login/verify/welcome for the entitlement gate.
      if (goingToLogin || goingToVerify || goingToWelcome || goingToBootstrapFail) {
        return '/gate';
      }
      if (goingToGate || goingToPromo || goingToLocked || goingToRecovery || goingToRestore) {
        return null;
      }
      // Onboarding + shell only after entitlement (or gate-off soft-pass) resolved.
      // Do NOT allow /onboarding without postAuthResolved — that skipped promo.
      if ((goingToOnboarding || inShell || goingToBillingTabs) &&
          !postAuthResolved) {
        return '/gate';
      }
      if (goingToOnboarding || inShell || goingToBillingTabs) {
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
      GoRoute(path: '/locked', builder: (c, s) => const LockedAccessScreen()),
      GoRoute(
        path: '/recovery',
        builder: (c, s) => RecoveryCodeScreen(
          code: s.uri.queryParameters['code'] ?? pendingRecoveryCode,
        ),
      ),
      GoRoute(
        path: '/restore',
        builder: (c, s) => const RestoreAccessScreen(),
      ),
      GoRoute(
        path: '/bootstrap-failed',
        builder: (c, s) => const BootstrapFailedScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (c, s) => const OnboardingScreen(),
      ),
      // Parked for later (not in bottom nav).
      GoRoute(
        path: '/subscription',
        builder: (c, s) => const SubscriptionTabScreen(),
      ),
      GoRoute(
        path: '/premium',
        builder: (c, s) => const PremiumTabScreen(),
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
                    path: 'account',
                    builder: (c, s) => const AccountHubScreen(),
                    routes: [
                      GoRoute(
                        path: 'telegram',
                        builder: (c, s) => const TelegramLinkScreen(),
                      ),
                      GoRoute(
                        path: 'email',
                        builder: (c, s) => const EmailLinkScreen(),
                      ),
                      GoRoute(
                        path: 'promo',
                        builder: (c, s) => const AccountPromoScreen(),
                      ),
                      GoRoute(
                        path: 'recovery',
                        builder: (c, s) => const RestoreAccessScreen(),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'devices',
                    builder: (c, s) => const DevicesScreen(),
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
