import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/application/auth_provider.dart';
import '../../auth/application/auth_state.dart';
import '../../auth/application/logout_handler.dart';
import '../../onboarding/data/onboarding_prefs.dart';
import '../application/beta_providers.dart';
import '../application/post_auth_router.dart';
import '../data/jwt_subject.dart';

/// Resolves entitlement → promo / onboarding / home after auth.
///
/// Network / Dio failures MUST NOT soft-pass into the shell. Closed-beta gates
/// stay authoritative; unreachable API → retry UI, not home with VPN.
class PostAuthGateScreen extends ConsumerStatefulWidget {
  const PostAuthGateScreen({super.key});

  @override
  ConsumerState<PostAuthGateScreen> createState() => _PostAuthGateScreenState();
}

class _PostAuthGateScreenState extends ConsumerState<PostAuthGateScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolve());
  }

  Future<void> _resolve() async {
    final auth = ref.read(authProvider).valueOrNull;
    if (auth is! AuthStateAuthenticated) {
      if (mounted) context.go('/login');
      return;
    }
    final userId = jwtSubject(auth.accessToken) ?? 'unknown';
    try {
      final entitlement = await ref.read(betaApiProvider).fetchEntitlement();
      final dest = await PostAuthRouter.resolveWithPrefs(
        entitlement: entitlement,
        userId: userId,
      );
      if (!mounted) return;
      AppRouter.postAuthResolved = true;
      switch (dest) {
        case PostAuthDestination.promo:
          // Promo must complete before shell; keep gate unresolved for /home.
          AppRouter.postAuthResolved = false;
          context.go('/promo');
        case PostAuthDestination.onboarding:
          context.go('/onboarding');
        case PostAuthDestination.home:
          context.go('/home');
      }
    } on DioException catch (e) {
      if (!mounted) return;
      if (e.response?.statusCode == 401) {
        AppRouter.postAuthResolved = false;
        await ref.read(logoutHandlerProvider).logout();
        if (mounted) context.go('/login');
        return;
      }
      // Socket / timeout / 5xx: stay on gate with retry. Never soft-pass.
      AppRouter.postAuthResolved = false;
      setState(() => _error = e.message ?? e.toString());
    } catch (e) {
      if (!mounted) return;
      AppRouter.postAuthResolved = false;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: _error == null
            ? const CircularProgressIndicator()
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AppIcon(AppIcons.warning, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      l.betaGateError,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () {
                        setState(() => _error = null);
                        _resolve();
                      },
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
  if (context.mounted) context.go('/login');
}
