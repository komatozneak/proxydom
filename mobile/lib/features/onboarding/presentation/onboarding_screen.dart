import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/diagnostics/ui_log.dart';
import '../../../core/router.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../data/onboarding_prefs.dart';

/// Connect-card copy: iOS must not mention Android VPN permission.
String onboardingConnectBodyForPlatform(AppL10n l) {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    return l.onboardingConnectBodyIos;
  }
  return l.onboardingConnectBody;
}

Color onboardingGlyphColor(ColorScheme scheme) => scheme.onSurface;

Color onboardingInactiveDotColor(ColorScheme scheme) => scheme.outline;

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

/// Post-entitlement cards (Connect / region). Skip marks completion.
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

  List<_OnboardingCard> _cards(AppL10n l) {
    return [
      _OnboardingCard(
        icon: AppIcons.shield,
        title: l.freeOnboardTitle,
        body: l.freeOnboardBody,
      ),
      _OnboardingCard(
        icon: AppIcons.clipboard,
        title: l.freeOnboardAddTitle,
        body: l.freeOnboardAddBody,
      ),
      _OnboardingCard(
        // The copy says "tap the house"; the card has to be a house. A power
        // glyph taught a different control than the one on Home.
        icon: AppIcons.houseFill,
        title: l.freeOnboardConnectTitle,
        body: l.freeOnboardConnectBody,
      ),
    ];
  }

  Future<void> _finish({bool openImport = false}) async {
    UiLog.action(
      'onboarding',
      'finish',
      extra: {'route': openImport ? '/import' : '/home'},
    );
    await OnboardingPrefs.markWelcomeSeen();
    AppRouter.welcomeSeenCache = true;
    if (!mounted) return;
    // Same push as Home, so «Добавить» has a back path to the house.
    context.go('/home');
    if (!openImport) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppRouter.config.push('/import');
    });
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
                            color: onboardingGlyphColor(theme.colorScheme),
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
                            color: theme.colorScheme.onSurfaceVariant,
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
                        : onboardingInactiveDotColor(theme.colorScheme),
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => _index >= cards.length - 1
                      ? _finish(openImport: true)
                      : _next(cards.length),
                  child: Text(
                    _index >= cards.length - 1
                        ? l.freeAddServer
                        : l.onboardingNext,
                  ),
                ),
              ),
            ),
            if (_index >= cards.length - 1)
              TextButton(
                onPressed: _finish,
                child: Text(l.freeLater),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
