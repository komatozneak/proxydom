import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config.dart';
import '../../../core/router.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/teremok_snackbar.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/application/auth_provider.dart';
import '../../auth/application/auth_state.dart';
import '../../auth/application/logout_handler.dart';
import '../../onboarding/data/onboarding_prefs.dart';
import '../../vpn/data/vpn_controller.dart';
import '../application/beta_providers.dart';
import '../application/post_auth_router.dart';
import '../data/jwt_subject.dart';

/// Resolves entitlement → promo / onboarding / home after auth.
///
/// Network / Dio failures MUST NOT soft-pass into the shell. Closed-beta gates
/// stay authoritative; unreachable API → retry UI, not home with VPN.
///
/// When another VPN / Always-on blocks the network, show conflict UX with a
/// deep-link to Android VPN settings (same path as Home Nest Connect).
class PostAuthGateScreen extends ConsumerStatefulWidget {
  const PostAuthGateScreen({super.key});

  @override
  ConsumerState<PostAuthGateScreen> createState() => _PostAuthGateScreenState();
}

class _PostAuthGateScreenState extends ConsumerState<PostAuthGateScreen> {
  /// Non-null when entitlement failed for a non-conflict reason.
  String? _error;

  /// True when [queryVpnConflict] reports a blocking foreign Always-on / lockdown.
  bool _vpnConflict = false;

  /// Optional label of the conflicting app (may be empty on Android 12+).
  String? _conflictAppLabel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolve());
  }

  Future<void> _resolve() async {
    final auth = ref.read(authProvider).valueOrNull;
    if (auth is! AuthStateAuthenticated) {
      if (!mounted) return;
      if (AppConfig.authAnonymous) {
        context.go('/bootstrap-failed');
      } else {
        context.go('/login');
      }
      return;
    }
    final userId = jwtSubject(auth.accessToken) ?? 'unknown';
    Object? lastError;
    // Activity recreate / VPN flap can abort the first entitlement call
    // (see Pixel log: Impeller restart mid-gate → betaGateError).
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final entitlement = await ref.read(betaApiProvider).fetchEntitlement();
        final dest = await PostAuthRouter.resolveWithPrefs(
          entitlement: entitlement,
          userId: userId,
        );
        if (!mounted) return;
        switch (dest) {
          case PostAuthDestination.promo:
            AppRouter.postAuthResolved = false;
            context.go('/promo');
          case PostAuthDestination.locked:
            AppRouter.postAuthResolved = false;
            context.go('/locked');
          case PostAuthDestination.onboarding:
            await AppRouter.goAfterEntitlement(context, '/onboarding');
          case PostAuthDestination.home:
            await AppRouter.goAfterEntitlement(context, '/home');
        }
        return;
      } on DioException catch (e) {
        lastError = e;
        if (e.response?.statusCode == 401) {
          if (!mounted) return;
          AppRouter.postAuthResolved = false;
          if (AppConfig.authAnonymous) {
            await ref.read(authProvider.notifier).retryBootstrap();
            if (mounted) context.go('/gate');
          } else {
            await ref.read(logoutHandlerProvider).logout();
            if (mounted) context.go('/login');
          }
          return;
        }
        final transient = e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.sendTimeout;
        if (transient && attempt < 2) {
          await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
          continue;
        }
        break;
      } catch (e) {
        lastError = e;
        break;
      }
    }
    if (!mounted) return;
    AppRouter.postAuthResolved = false;

    final conflict = await VpnController.instance.queryVpnConflict();
    if (!mounted) return;
    if (conflict.foreignAlwaysOn) {
      final label = conflict.appLabel?.trim();
      setState(() {
        _vpnConflict = true;
        _conflictAppLabel =
            (label != null && label.isNotEmpty) ? label : null;
        _error = lastError?.toString() ?? 'vpn_conflict';
      });
      return;
    }

    setState(() {
      _vpnConflict = false;
      _conflictAppLabel = null;
      _error = lastError?.toString() ?? 'unknown';
    });
  }

  void _retry() {
    setState(() {
      _error = null;
      _vpnConflict = false;
      _conflictAppLabel = null;
    });
    _resolve();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    final loading = _error == null && !_vpnConflict;

    return Scaffold(
      body: Center(
        child: loading
            ? const CircularProgressIndicator()
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AppIcon(AppIcons.warning, size: 48),
                    const SizedBox(height: 16),
                    if (_vpnConflict) ...[
                      Text(
                        l.homeVpnConflictTitle,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _conflictAppLabel != null
                            ? l.homeVpnConflictHintNamed(_conflictAppLabel!)
                            : l.homeVpnConflictHint,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 16),
                      FilledButton.tonal(
                        onPressed: () async {
                          final opened =
                              await VpnController.instance.openVpnSettings();
                          if (!context.mounted) return;
                          if (!opened) {
                            showTeremokSnackBar(
                              context,
                              l.settingsKillSwitchOpenFailed,
                            );
                          }
                        },
                        child: Text(l.settingsKillSwitchOpenVpn),
                      ),
                      const SizedBox(height: 12),
                    ] else ...[
                      Text(
                        l.betaGateError,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 16),
                    ],
                    FilledButton(
                      onPressed: _retry,
                      child: Text(l.homeRetry),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// Marks welcome seen so cold-start unauth users skip the splash next time.
Future<void> markWelcomeAndGoLogin(BuildContext context) async {
  await OnboardingPrefs.markWelcomeSeen();
  AppRouter.welcomeSeenCache = true;
  if (!context.mounted) return;
  if (AppConfig.authAnonymous) {
    context.go('/home');
    return;
  }
  context.go('/login');
}
