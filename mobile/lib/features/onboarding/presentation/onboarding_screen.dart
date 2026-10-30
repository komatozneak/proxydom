import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/diagnostics/ui_log.dart';
import '../../../core/ios_store_gates.dart';
import '../../../core/router.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_surface.dart';
import '../../../l10n/app_localizations.dart';
import '../../vpn/data/subscription_link_inbox.dart';
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
    // A key shared into the app before the welcome screens were done is held in
    // the inbox; the redirect sent it to onboarding, so this is the only place
    // left that can hand it to the import screen. Without this the person
    // finished onboarding on an empty Home and the key was never shown.
    final pendingLink = SubscriptionLinkInbox.hasPending;
    UiLog.action(
      'onboarding',
      'finish',
      extra: {
        'route': openImport || pendingLink ? '/import' : '/home',
        if (pendingLink) 'pending_link': true,
      },
    );
    await OnboardingPrefs.markWelcomeSeen();
    AppRouter.welcomeSeenCache = true;
    if (!mounted) return;
    // Same push as Home, so «Добавить» has a back path to the house.
    context.go('/home');
    if (!openImport && !pendingLink) return;
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

  /// Windows has no mobile permission pages and nothing to swipe through.
  /// One panel, one decision: add a server, or go to Home and do it later.
  Widget _windowsWelcome(AppL10n l, ThemeData theme) {
    final scheme = theme.colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: AppSurface(
                padding: const EdgeInsets.fromLTRB(36, 34, 36, 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppBrand.secondary.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: AppIcon(
                            AppIcons.shield,
                            size: 22,
                            color: scheme.onSurface,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          l.appTitle,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'WINDOWS',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            letterSpacing: 1.4,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 34),
                    Text(
                      l.pcOnboardHeadline,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l.pcOnboardBody,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const AppIcon(
                          AppIcons.shieldCheck,
                          size: 18,
                          color: AppBrand.secondary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            l.pcOnboardPrivacy,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        FilledButton(
                          onPressed: () => _finish(openImport: true),
                          child: Text(l.freeAddServer),
                        ),
                        TextButton(
                          onPressed: _finish,
                          child: Text(l.freeLater),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    if (windowsDesktop) return _windowsWelcome(l, theme);
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
                            color: AppBrand.secondary.withValues(alpha: 0.15),
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
            Text(
              '${_index + 1} / ${cards.length}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
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
