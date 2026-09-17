import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config.dart';
import '../../../core/diagnostics/app_log_buffer.dart';
import '../../../core/router.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/teremok_snackbar.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/application/auth_provider.dart';
import '../../auth/application/auth_state.dart';
import '../../auth/application/logout_handler.dart';
import '../../auth/presentation/bootstrap_loading_screen.dart';
import '../../onboarding/data/onboarding_prefs.dart';
import '../../vpn/data/vpn_controller.dart';
import '../application/beta_providers.dart';
import '../application/post_auth_router.dart';
import '../data/jwt_subject.dart';

/// How long a single entitlement call may hang on /gate (dead Packet Tunnel).
@visibleForTesting
const Duration kGateEntitlementTimeout = Duration(seconds: 2);

const kGateRetryKey = ValueKey<String>('gate_retry');
const kGateDisconnectVpnKey = ValueKey<String>('gate_disconnect_vpn');

/// Resolves entitlement → promo / onboarding / home after auth.
///
/// Network / Dio failures MUST NOT soft-pass into the shell. Closed-beta gates
/// stay authoritative; unreachable API → retry UI, not home with VPN.
///
/// When another VPN / Always-on blocks the network, show conflict UX with a
/// deep-link to Android VPN settings (same path as Home Nest Connect).
///
/// Own Packet Tunnel is never auto-stopped (iOS UI ≠ dataplane). Only the
/// manual «Отключить VPN и повторить» CTA calls [VpnController.stop].
class PostAuthGateScreen extends ConsumerStatefulWidget {
  const PostAuthGateScreen({super.key});

  @override
  ConsumerState<PostAuthGateScreen> createState() => _PostAuthGateScreenState();
}

class _PostAuthGateScreenState extends ConsumerState<PostAuthGateScreen> {
  /// Non-null when entitlement failed for a non-conflict reason.
  String? _errorKind;

  /// True when [queryVpnConflict] reports a blocking foreign Always-on / lockdown.
  bool _vpnConflict = false;

  /// Optional label of the conflicting app (may be empty on Android 12+).
  String? _conflictAppLabel;

  /// Own Packet Tunnel / VpnService still up — offer disconnect CTA.
  bool _ownVpnActive = false;

  bool _resolving = false;
  bool _did401Recover = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolve());
  }

  Future<void> _resolve({bool stopOwnVpnFirst = false}) async {
    if (_resolving) return;
    _resolving = true;
    AppLogBuffer.instance.info(
      'gate.resolve start stopOwnVpnFirst=$stopOwnVpnFirst',
    );
    try {
      if (mounted) {
        setState(() {
          _errorKind = null;
          _vpnConflict = false;
          _conflictAppLabel = null;
        });
      }

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

      // Manual CTA only — never auto-stop leftover own tunnel for entitlement.
      if (stopOwnVpnFirst) {
        await _stopOwnTunnelQuietly(reason: 'manual_cta');
      }

      final userId = jwtSubject(auth.accessToken) ?? 'unknown';
      Object? lastError;
      // Short attempts: dead Hy2 tunnel used to hang 30s/60s × 3.
      for (var attempt = 0; attempt < 2; attempt++) {
        final sw = Stopwatch()..start();
        try {
          final entitlement = await ref
              .read(betaApiProvider)
              .fetchEntitlement()
              .timeout(
                kGateEntitlementTimeout,
                onTimeout: () => throw DioException(
                  requestOptions: RequestOptions(path: '/beta/entitlement'),
                  type: DioExceptionType.connectionTimeout,
                  message: 'gate entitlement timeout',
                ),
              );
          AppLogBuffer.instance.info(
            'gate.entitlement ok ms=${sw.elapsedMilliseconds} attempt=$attempt',
          );
          final dest = await PostAuthRouter.resolveWithPrefs(
            entitlement: entitlement,
            userId: userId,
          );
          if (!mounted) return;
          _did401Recover = false;
          AppLogBuffer.instance.info('gate.dest=${dest.name}');
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
          AppLogBuffer.instance.warn(
            'gate.entitlement fail ms=${sw.elapsedMilliseconds} '
            'attempt=$attempt type=${e.type.name} '
            'status=${e.response?.statusCode ?? '-'}',
          );
          if (e.response?.statusCode == 401) {
            if (!mounted) return;
            AppRouter.postAuthResolved = false;
            if (AppConfig.authAnonymous) {
              if (!_did401Recover) {
                _did401Recover = true;
                AppLogBuffer.instance.info('gate.401 retryBootstrap');
                await ref.read(authProvider.notifier).retryBootstrap();
                // Re-enter resolve on the same /gate route (go('/gate') is a no-op).
                _resolving = false;
                await _resolve(stopOwnVpnFirst: stopOwnVpnFirst);
                return;
              }
              break;
            }
            await ref.read(logoutHandlerProvider).logout();
            if (mounted) context.go('/login');
            return;
          }
          final transient = e.type == DioExceptionType.connectionError ||
              e.type == DioExceptionType.connectionTimeout ||
              e.type == DioExceptionType.receiveTimeout ||
              e.type == DioExceptionType.sendTimeout;
          if (transient && attempt < 1) {
            await Future<void>.delayed(Duration(milliseconds: 300 * (attempt + 1)));
            continue;
          }
          break;
        } catch (e) {
          lastError = e;
          AppLogBuffer.instance.warn(
            'gate.entitlement fail ms=${sw.elapsedMilliseconds} '
            'attempt=$attempt err=$e',
          );
          break;
        }
      }

      if (!mounted) return;
      AppRouter.postAuthResolved = false;

      final ownVpn = await _isOwnVpnActive();
      final conflict = await VpnController.instance.queryVpnConflict();
      if (!mounted) return;
      if (conflict.foreignAlwaysOn) {
        final label = conflict.appLabel?.trim();
        setState(() {
          _vpnConflict = true;
          _conflictAppLabel =
              (label != null && label.isNotEmpty) ? label : null;
          _ownVpnActive = ownVpn;
          _errorKind = 'vpn_conflict';
        });
        return;
      }

      setState(() {
        _vpnConflict = false;
        _conflictAppLabel = null;
        _ownVpnActive = ownVpn;
        _errorKind = _classifyError(lastError);
      });
      AppLogBuffer.instance.warn(
        'gate.error kind=$_errorKind ownVpn=$ownVpn',
      );
    } finally {
      _resolving = false;
    }
  }

  Future<bool> _isOwnVpnActive() async {
    try {
      final session = await VpnController.instance.hasActiveSession();
      final status = await VpnController.instance.getStatus();
      final active = session ||
          status == VpnNativeStatus.connected ||
          status == VpnNativeStatus.connecting;
      AppLogBuffer.instance.info(
        'gate.vpn_probe session=$session status=${status.name} active=$active',
      );
      return active;
    } catch (e) {
      AppLogBuffer.instance.warn('gate.vpn_probe fail: $e');
      return false;
    }
  }

  Future<void> _stopOwnTunnelQuietly({required String reason}) async {
    try {
      AppLogBuffer.instance.info('gate.stop_own_tunnel reason=$reason');
      await VpnController.instance.stop(reason: 'gate_manual');
    } catch (e) {
      AppLogBuffer.instance.warn('gate.stop_own_tunnel fail: $e');
      // Missing plugin / already idle — still try entitlement over LTE.
    }
  }

  static String _classifyError(Object? error) {
    if (error is DioException) {
      if (error.response?.statusCode == 401) return 'unauthorized';
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          (error.message?.contains('timeout') ?? false)) {
        return 'timeout';
      }
      if (error.type == DioExceptionType.connectionError) return 'network';
    }
    if (error is TimeoutException) return 'timeout';
    return 'unknown';
  }

  String _errorMessage(AppL10n l) {
    switch (_errorKind) {
      case 'timeout':
        return l.betaGateErrorTimeout;
      case 'unauthorized':
        return l.betaGateErrorUnauthorized;
      case 'network':
        return l.networkErrorFriendly;
      default:
        return l.betaGateError;
    }
  }

  void _retry({required bool stopVpn}) {
    if (_resolving) return;
    _did401Recover = false;
    AppLogBuffer.instance.info('gate.retry stopVpn=$stopVpn');
    setState(() {
      _errorKind = null;
      _vpnConflict = false;
      _conflictAppLabel = null;
      _ownVpnActive = false;
    });
    _resolve(stopOwnVpnFirst: stopVpn);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    final loading = _errorKind == null && !_vpnConflict;

    return Scaffold(
      body: Center(
        child: loading
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppIcon(AppIcons.house, size: 48),
                  const SizedBox(height: 24),
                  CircularProgressIndicator(
                    key: BootstrapLoadingScreen.progressKey,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l.betaGateChecking,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge,
                  ),
                ],
              )
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
                        onPressed: _resolving
                            ? null
                            : () async {
                                final opened = await VpnController.instance
                                    .openVpnSettings();
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
                        _errorMessage(l),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 16),
                    ],
                    FilledButton(
                      key: kGateRetryKey,
                      onPressed:
                          _resolving ? null : () => _retry(stopVpn: false),
                      child: Text(l.homeRetry),
                    ),
                    if (_ownVpnActive ||
                        _errorKind == 'timeout' ||
                        _errorKind == 'network') ...[
                      const SizedBox(height: 12),
                      FilledButton.tonal(
                        key: kGateDisconnectVpnKey,
                        onPressed: _resolving
                            ? null
                            : () => _retry(stopVpn: true),
                        child: Text(l.betaGateDisconnectVpnRetry),
                      ),
                    ],
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
    // Post-logout/expiry landing: nothing auto-registers anymore, so the
    // Continue CTA explicitly starts a fresh anonymous account.
    final container = ProviderScope.containerOf(context, listen: false);
    final auth = container.read(authProvider).valueOrNull;
    if (auth is! AuthStateAuthenticated) {
      await container.read(authProvider.notifier).retryBootstrap();
    }
    if (!context.mounted) return;
    context.go('/home');
    return;
  }
  context.go('/login');
}
