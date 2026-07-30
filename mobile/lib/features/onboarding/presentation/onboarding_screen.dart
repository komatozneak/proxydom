import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/application/auth_provider.dart';
import '../../auth/application/auth_state.dart';
import '../../beta/application/beta_usage_tracker.dart';
import '../../beta/data/jwt_subject.dart';
import '../data/onboarding_prefs.dart';

class _OnboardingCard {
  const _OnboardingCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;
}

/// Post-entitlement cards (Connect / region / help). Skip marks completion.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  var _index = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  List<_OnboardingCard> _cards(AppL10n l) => [
        _OnboardingCard(
          icon: AppIcons.power,
          title: l.onboardingConnectTitle,
          body: l.onboardingConnectBody,
        ),
        _OnboardingCard(
          icon: AppIcons.servers,
          title: l.onboardingRegionTitle,
          body: l.onboardingRegionBody,
        ),
        _OnboardingCard(
          icon: AppIcons.info,
          title: l.onboardingHelpTitle,
          body: l.onboardingHelpBody,
        ),
      ];

  Future<void> _finish() async {
    final auth = ref.read(authProvider).valueOrNull;
    final userId = auth is AuthStateAuthenticated
        ? (jwtSubject(auth.accessToken) ?? 'unknown')
        : 'unknown';
    await OnboardingPrefs.markCompleted(userId: userId);
    ref.read(betaUsageTrackerProvider).recordOnboardingCompleted();
    AppRouter.postAuthResolved = true;
    if (mounted) context.go('/home');
  }

  void _next(int total) {
    if (_index >= total - 1) {
      _finish();
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    final cards = _cards(l);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _finish,
                child: Text(l.onboardingSkip),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: cards.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) {
                  final card = cards[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            color: AppBrand.secondary.withOpacity(0.15),
                            shape: BoxShape.circle,
                          ),
                          child: AppIcon(
                            card.icon,
                            size: 44,
                            color: AppBrand.primary,
                          ),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          card.title,
                          style: theme.textTheme.headlineSmall,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          card.body,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.75),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(cards.length, (i) {
                final active = i == _index;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: active ? 18 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: active
                        ? AppBrand.secondary
                        : AppBrand.primary.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: FilledButton(
                onPressed: () => _next(cards.length),
                child: Text(
                  _index >= cards.length - 1
                      ? l.onboardingDone
                      : l.onboardingNext,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
