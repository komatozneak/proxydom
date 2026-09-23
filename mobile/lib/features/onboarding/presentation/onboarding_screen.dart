import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ios_store_gates.dart';
import '../../../core/router.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/application/auth_provider.dart';
import '../../auth/application/auth_state.dart';
import '../../beta/application/beta_usage_tracker.dart';
import '../../beta/data/jwt_subject.dart';
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
    if (freeKeyClient) {
      final ru = Localizations.localeOf(context).languageCode == 'ru';
      return [
        _OnboardingCard(
          icon: AppIcons.shield,
          title: ru ? 'Теремок — бесплатный клиент' : 'Teremok is a free client',
          body: ru
              ? 'Приложение бесплатное и без рекламы. Доступ не продаётся внутри. Подключение — по вашей ссылке.'
              : 'The app is free and has no ads. Access is not sold inside. You connect with your own link.',
        ),
        _OnboardingCard(
          icon: AppIcons.servers,
          title: ru
              ? 'Серверы — от вашего провайдера'
              : 'Servers come from your provider',
          body: ru
              ? 'Своих серверов в приложении нет. Ссылку на подписку даёт провайдер, в том числе бот Теремка.'
              : 'This app does not ship its own server list. A provider, including the Teremok bot, gives you a subscription link.',
        ),
        _OnboardingCard(
          icon: AppIcons.clipboard,
          title: ru ? 'Добавьте подписку' : 'Add a subscription',
          body: ru
              ? 'Вставьте ссылку или отсканируйте QR — серверы появятся в списке.'
              : 'Paste a link or scan a QR code and the servers show up in the list.',
        ),
      ];
    }
    return [
        _OnboardingCard(
          icon: AppIcons.power,
          title: l.onboardingConnectTitle,
          body: onboardingConnectBodyForPlatform(l),
        ),
        _OnboardingCard(
          icon: AppIcons.servers,
          title: l.onboardingRegionTitle,
          body: l.onboardingRegionBody,
        ),
      ];
  }

  Future<void> _finish({bool openImport = false}) async {
    if (freeKeyClient) {
      await OnboardingPrefs.markWelcomeSeen();
      AppRouter.welcomeSeenCache = true;
      if (mounted) context.go(openImport ? '/import' : '/home');
      return;
    }
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
                  onPressed: () => freeKeyClient && _index >= cards.length - 1
                      ? _finish(openImport: true)
                      : _next(cards.length),
                  child: Text(
                    freeKeyClient && _index >= cards.length - 1
                        ? (Localizations.localeOf(context).languageCode == 'ru'
                            ? 'Добавить подписку'
                            : 'Add subscription')
                        : (_index >= cards.length - 1
                            ? l.onboardingDone
                            : l.onboardingNext),
                  ),
                ),
              ),
            ),
            if (freeKeyClient && _index >= cards.length - 1)
              TextButton(
                onPressed: _finish,
                child: Text(
                  Localizations.localeOf(context).languageCode == 'ru'
                      ? 'Позже'
                      : 'Later',
                ),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
