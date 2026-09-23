import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teremok_connect/core/ios_store_gates.dart';
import 'package:teremok_connect/features/auth/data/auth_api.dart';
import 'package:teremok_connect/features/beta/presentation/locked_access_screen.dart';
import 'package:teremok_connect/features/billing/presentation/premium_tab_screen.dart';
import 'package:teremok_connect/features/billing/presentation/subscription_tab_screen.dart';
import 'package:teremok_connect/features/settings/application/devices_list_provider.dart';
import 'package:teremok_connect/features/settings/application/subscription_status_provider.dart';
import 'package:teremok_connect/features/settings/data/subscription_status.dart';
import 'package:teremok_connect/features/settings/presentation/settings_screen.dart';
import 'package:teremok_connect/features/onboarding/presentation/onboarding_screen.dart';
import 'package:teremok_connect/features/vpn/presentation/vpn_platform_copy.dart';
import 'package:teremok_connect/l10n/app_localizations.dart';

class _FixedSubNotifier extends SubscriptionStatusNotifier {
  _FixedSubNotifier(this._status);

  final SubscriptionStatus _status;

  @override
  Future<SubscriptionStatus> build() async => _status;
}

class _EmptyDevices extends DevicesListNotifier {
  @override
  Future<DeviceListResult> build() async => const DeviceListResult(
        devices: [],
        activeCount: 0,
        maxDevices: 5,
      );
}

const _freeQuota = SubscriptionStatus(
  quotaBytesLimit: 1 << 32,
  quotaBytesRemaining: 1 << 31,
  quotaBytesUsed: 1 << 31,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('iOS copy is not a cashier or closed-beta wall', () {
    final ru = lookupAppL10n(const Locale('ru'));
    final en = lookupAppL10n(const Locale('en'));
    expect(ru.accountHubGuestLead.toLowerCase(), isNot(contains('чек')));
    expect(ru.recoveryCodeBody.toLowerCase(), isNot(contains('чек')));
    expect(ru.restoreBody.toLowerCase(), isNot(contains('platega')));
    expect(ru.restoreBodyCode.toLowerCase(), isNot(contains('platega')));
    expect(ru.promoBody.toLowerCase(), isNot(contains('бета')));
    expect(ru.regionBlurbFree, isNot(contains('нейросет')));
    expect(
        ru.iosBillingUnavailableBody.toLowerCase(), isNot(contains('android')));
    expect(
        ru.iosBillingUnavailableBody.toLowerCase(), isNot(contains('промо')));
    expect(ru.iosBillingUnavailableBody.toLowerCase(),
        isNot(contains('telegram')));
    expect(ru.iosBillingUnavailableBody.toLowerCase(), isNot(contains('t.me')));
    expect(en.iosBillingUnavailableBody.toLowerCase(),
        isNot(contains('telegram')));
    expect(ru.accountTelegramVpnRequired, 'Сначала подключитесь.');
    expect(
        ru.accountHubLinkTelegramHint.toLowerCase(), isNot(contains('оплат')));
    expect(ru.accountHubLinkTelegramHint, isNot(contains('₽')));
    expect(ru.accountHubLinkedLead.toLowerCase(), isNot(contains('оплат')));
    expect(ru.accountHubLinkedLeadIos.toLowerCase(), isNot(contains('оплат')));
    expect(
        ru.accountHubLinkedLeadIos.toLowerCase(), isNot(contains('подписк')));
    expect(ru.settingsSupportHintIos.toLowerCase(), isNot(contains('оплат')));
    expect(ru.restoreBodyCode.toLowerCase(), isNot(contains('оплат')));
    expect(ru.restoreBody.toLowerCase(), isNot(contains('оплат')));
    expect(ru.restoreBodyCodeIos.toLowerCase(), isNot(contains('оплат')));
    expect(en.settingsSupportHintIos.toLowerCase(), isNot(contains('pay')));
    expect(en.restoreBodyCode.toLowerCase(), isNot(contains('paid')));
    expect(en.restoreBody.toLowerCase(), isNot(contains('paid')));
    expect(
        ru.accountTelegramLinkedBody.toLowerCase(), isNot(contains('оплат')));
    expect(ru.accountHubLinkTelegramHint, contains('боте'));
    expect(en.accountHubLinkTelegramHint.toLowerCase(), isNot(contains('pay')));
    expect(en.accountHubLinkTelegramHint.toLowerCase(), contains('bot'));
    expect(en.regionBlurbFree.toLowerCase(), isNot(contains('ai')));
    expect(en.promoBody.toLowerCase(), isNot(contains('closed beta')));
    expect(en.restoreBody.toLowerCase(), isNot(contains('platega')));
    expect(en.accountTelegramVpnRequired, 'Connect first.');
  });

  test('location and premium copy has no circumvention freeze words', () {
    final ru = lookupAppL10n(const Locale('ru'));
    final en = lookupAppL10n(const Locale('en'));
    for (final s in [
      ru.regionBlurbYoutube,
      ru.regionBlurbIndia,
      ru.premiumHeadline,
      ru.premiumBody,
      ru.premiumFeatureYt,
      ru.subscriptionTabHint,
      en.regionBlurbYoutube,
      en.regionBlurbIndia,
      en.premiumHeadline,
      en.premiumBody,
      en.premiumFeatureYt,
      en.subscriptionTabHint,
    ]) {
      final lower = s.toLowerCase();
      expect(lower, isNot(contains('реклам')));
      expect(lower, isNot(contains('цен')));
      expect(lower, isNot(contains('нейросет')));
      expect(lower, isNot(contains('mid-roll')));
      expect(lower, isNot(contains('adsense')));
      expect(lower, isNot(contains('without ads')));
      expect(lower, isNot(contains('prices')));
    }
    expect(ru.regionBlurbYoutube, 'Комфортный просмотр');
    expect(en.regionBlurbYoutube, 'Comfortable streaming');
    expect(ru.onboardingConnectBodyIos, contains('iPhone'));
    expect(ru.onboardingConnectBodyIos, isNot(contains('Android')));
    expect(ru.homeVpnConflictHintIos.toLowerCase(), isNot(contains('android')));
    expect(
        ru.homeVpnPermissionHintIos.toLowerCase(), isNot(contains('android')));
    expect(ru.settingsKillSwitchOpenFailedIos.toLowerCase(),
        isNot(contains('android')));
    expect(ru.homeVpnConflictHint, contains('Android'));
    expect(ru.settingsReportCopied.toLowerCase(), isNot(contains('бот')));
    expect(en.settingsReportCopied.toLowerCase(), isNot(contains('bot')));
    expect(ru.settingsSendReportHint.toLowerCase(), isNot(contains('бот')));
    expect(en.settingsSendReportHint.toLowerCase(), isNot(contains('bot')));
  });

  test('iOS Home, gate, disclosure and onboarding copy has no Android', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final ru = lookupAppL10n(const Locale('ru'));
    final en = lookupAppL10n(const Locale('en'));
    for (final s in [
      ...visibleVpnGuidanceCopy(ru),
      onboardingConnectBodyForPlatform(ru),
      ...visibleVpnGuidanceCopy(en),
      onboardingConnectBodyForPlatform(en),
    ]) {
      expect(s.toLowerCase(), isNot(contains('android')));
    }
    expect(ru.onboardingConnectBody, contains('Android'));
    expect(en.homeVpnConflictHint, contains('Android'));
  });

  test('iOS Locations header is Сервис, Android stays Премиум', () {
    final ru = lookupAppL10n(const Locale('ru'));
    final en = lookupAppL10n(const Locale('en'));
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    expect(regionSectionYoutubeForPlatform(ru), 'Сервис');
    expect(regionSectionYoutubeForPlatform(ru), isNot(contains('Премиум')));
    expect(regionSectionYoutubeForPlatform(en), 'Services');
    expect(regionSectionYoutubeForPlatform(en).toLowerCase(),
        isNot(contains('premium')));
    expect(ru.settingsSupportHintIos, contains('боте'));
    expect(ru.settingsSupportHintIos.toLowerCase(), isNot(contains('оплат')));
    expect(ru.settingsSupportHintIos.toLowerCase(),
        isNot(contains('переустанов')));
    expect(accountHubLinkedLeadForPlatform(ru), ru.accountHubLinkedLeadIos);
    expect(restoreBodyCodeForPlatform(ru), ru.restoreBodyCodeIos);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(regionSectionYoutubeForPlatform(ru), 'Премиум');
    expect(regionSectionYoutubeForPlatform(en), 'Premium');
    expect(settingsSupportHintForPlatform(ru), ru.settingsSupportHint);
    expect(accountHubLinkedLeadForPlatform(ru), ru.accountHubLinkedLead);
    expect(restoreBodyCodeForPlatform(ru), ru.restoreBodyCode);
  });

  test('Android Home, gate and onboarding copy still mentions Android', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final ru = lookupAppL10n(const Locale('ru'));
    final en = lookupAppL10n(const Locale('en'));
    expect(visibleVpnGuidanceCopy(ru).join(' '), contains('Android'));
    expect(onboardingConnectBodyForPlatform(ru), contains('Android'));
    expect(visibleVpnGuidanceCopy(en).join(' '), contains('Android'));
    expect(onboardingConnectBodyForPlatform(en), contains('Android'));
  });

  testWidgets('iOS locked CTA without VPN asks to connect, not promo',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final container = ProviderContainer(
      overrides: [
        subscriptionStatusProvider.overrideWith(
          () => _FixedSubNotifier(_freeQuota),
        ),
        devicesListProvider.overrideWith(() => _EmptyDevices()),
      ],
    );
    addTearDown(container.dispose);

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, __) => const LockedAccessScreen()),
        GoRoute(
          path: '/settings/account',
          builder: (_, __) => const Text('ACCOUNT_HUB'),
        ),
        GoRoute(path: '/promo', builder: (_, __) => const Text('PROMO_DEAD')),
        GoRoute(path: '/import', builder: (_, __) => const Text('IMPORT_LINK')),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          locale: const Locale('ru'),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Код доступа'), findsNothing);
    expect(find.text('Тарифы'), findsNothing);
    expect(find.text('Код проверки: PLAT'), findsNothing);
    expect(find.text('Оплатить 199 ₽'), findsNothing);
    expect(
      find.text('Оформите подписку — и подключайтесь в один тап.'),
      findsNothing,
    );
    expect(find.textContaining('Telegram'), findsNothing);
    expect(
        find.text(
            'Оплата в приложении недоступна. Бесплатные локации работают.'),
        findsOneWidget);
    expect(find.text('Аккаунт'), findsWidgets);
    await tester.tap(find.widgetWithText(FilledButton, 'Аккаунт'));
    await tester.pumpAndSettle();
    expect(find.text('IMPORT_LINK'), findsOneWidget);
    expect(find.text('Сначала подключитесь.'), findsNothing);
    expect(find.text('ACCOUNT_HUB'), findsNothing);
    expect(find.text('PROMO_DEAD'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('iOS Premium tab without VPN asks to connect, not promo',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final container = ProviderContainer(
      overrides: [
        subscriptionStatusProvider.overrideWith(
          () => _FixedSubNotifier(_freeQuota),
        ),
      ],
    );
    addTearDown(container.dispose);

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, __) => const PremiumTabScreen()),
        GoRoute(
          path: '/settings/account',
          builder: (_, __) => const Text('ACCOUNT_HUB'),
        ),
        GoRoute(path: '/promo', builder: (_, __) => const Text('PROMO_DEAD')),
        GoRoute(path: '/import', builder: (_, __) => const Text('IMPORT_LINK')),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          locale: const Locale('ru'),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Код доступа'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, 'Аккаунт'));
    await tester.pumpAndSettle();
    expect(find.text('IMPORT_LINK'), findsOneWidget);
    expect(find.text('Сначала подключитесь.'), findsNothing);
    expect(find.text('ACCOUNT_HUB'), findsNothing);
    expect(find.text('PROMO_DEAD'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('iOS Settings footer hides pricing link', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final container = ProviderContainer(
      overrides: [
        subscriptionStatusProvider.overrideWith(
          () => _FixedSubNotifier(_freeQuota),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('ru'),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          home: SettingsScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(tester.takeException(), isNull);
    expect(find.text('Настройки'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Политика конфиденциальности'),
      400,
    );
    expect(find.text('Тарифы'), findsNothing);
    expect(find.text('Что работает без VPN?'), findsNothing);
    expect(find.text('Политика конфиденциальности'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('iOS Subscription shows Advanced features, not Account pay',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final container = ProviderContainer(
      overrides: [
        subscriptionStatusProvider.overrideWith(
          () => _FixedSubNotifier(_freeQuota),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('ru'),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          home: SubscriptionTabScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(kSubscriptionAdvancedKey), findsOneWidget);
    expect(find.text('Расширенные возможности'), findsOneWidget);
    expect(find.byKey(kSubscriptionPayKey), findsNothing);
    expect(find.text('Оплатить'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  test('iOS referral deep link does not open promo or account', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    expect(referralLandingPath, '/home');
    expect(referralLandingPath, isNot(contains('promo')));
    expect(iosFreeClientRouteBlocked('/settings/account'), isTrue);
  });
}
