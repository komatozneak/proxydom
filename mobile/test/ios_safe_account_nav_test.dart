import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teremok_connect/features/auth/data/auth_api.dart';
import 'package:teremok_connect/features/beta/presentation/locked_access_screen.dart';
import 'package:teremok_connect/features/billing/presentation/premium_tab_screen.dart';
import 'package:teremok_connect/features/settings/application/devices_list_provider.dart';
import 'package:teremok_connect/features/settings/application/subscription_status_provider.dart';
import 'package:teremok_connect/features/settings/data/subscription_status.dart';
import 'package:teremok_connect/features/settings/presentation/settings_screen.dart';
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
    expect(ru.iosBillingUnavailableBody.toLowerCase(), isNot(contains('android')));
    expect(ru.iosBillingUnavailableBody.toLowerCase(), isNot(contains('промо')));
    expect(ru.iosBillingUnavailableBody.toLowerCase(), isNot(contains('telegram')));
    expect(ru.iosBillingUnavailableBody.toLowerCase(), isNot(contains('t.me')));
    expect(en.iosBillingUnavailableBody.toLowerCase(), isNot(contains('telegram')));
    expect(ru.accountTelegramVpnRequired, 'Сначала подключитесь.');
    expect(en.regionBlurbFree.toLowerCase(), isNot(contains('ai')));
    expect(en.promoBody.toLowerCase(), isNot(contains('closed beta')));
    expect(en.restoreBody.toLowerCase(), isNot(contains('platega')));
    expect(en.accountTelegramVpnRequired, 'Connect first.');
  });

  testWidgets('iOS locked CTA opens Account, not promo', (tester) async {
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
    expect(find.textContaining('Telegram'), findsNothing);
    expect(find.text('Аккаунт'), findsWidgets);
    await tester.tap(find.widgetWithText(FilledButton, 'Аккаунт'));
    await tester.pumpAndSettle();
    expect(find.text('ACCOUNT_HUB'), findsOneWidget);
    expect(find.text('PROMO_DEAD'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('iOS Premium tab opens Account, not promo', (tester) async {
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
    expect(find.text('ACCOUNT_HUB'), findsOneWidget);
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
    expect(find.text('Политика конфиденциальности'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
}
