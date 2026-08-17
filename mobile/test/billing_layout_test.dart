import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/features/auth/data/auth_api.dart';
import 'package:teremok_connect/features/beta/presentation/locked_access_screen.dart';
import 'package:teremok_connect/features/billing/presentation/subscription_tab_screen.dart';
import 'package:teremok_connect/features/settings/application/devices_list_provider.dart';
import 'package:teremok_connect/features/settings/application/subscription_status_provider.dart';
import 'package:teremok_connect/features/settings/data/subscription_status.dart';
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

Widget _app({
  required ProviderContainer container,
  required Widget home,
}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      locale: const Locale('ru'),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      home: home,
    ),
  );
}

void main() {
  testWidgets('Subscription keeps Pay above promo and drops hint copy',
      (tester) async {
    final container = ProviderContainer(
      overrides: [
        subscriptionStatusProvider.overrideWith(
          () => _FixedSubNotifier(_freeQuota),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _app(container: container, home: const SubscriptionTabScreen()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(kSubscriptionPayKey), findsOneWidget);
    expect(find.byKey(kSubscriptionPromoKey), findsOneWidget);
    expect(
      find.text('Тарифы и промокоды. Премиум открывает YouTube-локации.'),
      findsNothing,
    );
    expect(find.text('Оплатить'), findsOneWidget);
    expect(find.text('Или введите промокод'), findsOneWidget);

    final payY = tester.getTopLeft(find.byKey(kSubscriptionPayKey)).dy;
    final promoY = tester.getTopLeft(find.byKey(kSubscriptionPromoKey)).dy;
    expect(payY, lessThan(promoY));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Activation keeps pay card above centered footer',
      (tester) async {
    final container = ProviderContainer(
      overrides: [
        subscriptionStatusProvider.overrideWith(
          () => _FixedSubNotifier(_freeQuota),
        ),
        devicesListProvider.overrideWith(() => _EmptyDevices()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _app(container: container, home: const LockedAccessScreen()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(kLockedPayCardKey), findsOneWidget);
    expect(find.byKey(kLockedFooterKey), findsOneWidget);
    expect(find.byKey(kLockedPayCtaKey), findsOneWidget);
    expect(find.text('Тарифы'), findsOneWidget);
    expect(find.text('Поддержка'), findsOneWidget);
    expect(find.text('1 месяц'), findsOneWidget);
    expect(find.text('3 месяца'), findsOneWidget);
    expect(find.text('6 месяцев'), findsOneWidget);
    expect(find.text('12 месяцев'), findsOneWidget);
    expect(find.text('Оплатить 199 ₽'), findsOneWidget);
    expect(find.text('929 ₽'), findsOneWidget);
    expect(find.text('1490 ₽'), findsOneWidget);
    expect(find.text('Код проверки: PLAT'), findsOneWidget);
    expect(find.text('Удаление аккаунта'), findsOneWidget);

    await tester.ensureVisible(find.text('12 месяцев'));
    await tester.tap(find.text('12 месяцев'));
    await tester.pump();
    expect(find.text('Оплатить 1490 ₽'), findsOneWidget);

    final cardY = tester.getTopLeft(find.byKey(kLockedPayCardKey)).dy;
    final footerY = tester.getTopLeft(find.byKey(kLockedFooterKey)).dy;
    expect(cardY, lessThan(footerY));
    expect(tester.takeException(), isNull);
  });
}
