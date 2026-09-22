import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/core/theme.dart';
import 'package:teremok_connect/core/widgets/app_icon.dart';
import 'package:teremok_connect/features/auth/data/auth_api.dart';
import 'package:teremok_connect/features/settings/application/devices_list_provider.dart';
import 'package:teremok_connect/features/settings/presentation/devices_screen.dart';
import 'package:teremok_connect/l10n/app_localizations.dart';

class _FixedDevicesNotifier extends DevicesListNotifier {
  _FixedDevicesNotifier(this.result);

  final DeviceListResult result;

  @override
  Future<DeviceListResult> build() async => result;
}

Widget _app(DeviceListResult data) {
  return ProviderScope(
    overrides: [
      devicesListProvider.overrideWith(() => _FixedDevicesNotifier(data)),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      locale: const Locale('ru'),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      home: const DevicesScreen(),
    ),
  );
}

DeviceSlot _slot({
  required int id,
  required bool current,
  required bool owner,
  String name = 'Android',
}) {
  return DeviceSlot(
    id: id,
    status: 'active',
    createdAt: DateTime.utc(2026, 8, 15, 6, 34),
    deviceName: name,
    platform: 'android',
    lastSeenAt: DateTime.utc(2026, 8, 15, 6, 34),
    isCurrent: current,
    seatRole: owner ? 'owner' : 'member',
    isOwner: owner,
  );
}

void main() {
  // CI runs `flutter test --dart-define=AUTH_ANONYMOUS=false`, which hides the
  // Join row behind AppConfig.authAnonymous. These tests cover the production
  // anonymous-auth UI, so skip them when the flag is off.
  const anonymous = bool.fromEnvironment('AUTH_ANONYMOUS', defaultValue: true);

  testWidgets(
    'solo member sees Join, not Invite',
    skip: !anonymous,
    (tester) async {
    await tester.pumpWidget(
      _app(
        DeviceListResult(
          activeCount: 1,
          maxDevices: 5,
          devices: [_slot(id: 1, current: true, owner: false)],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Войти в группу'), findsOneWidget);
    expect(find.text('Присоединиться по приглашению'), findsOneWidget);
    expect(find.byIcon(AppIcons.signIn), findsOneWidget);
    expect(find.text('Добавить устройство в подписку'), findsNothing);
    expect(find.text('Выйти на всех устройствах'), findsNothing);
    expect(find.text('Android'), findsOneWidget);
    expect(find.text('Это устройство'), findsOneWidget);
    expect(find.byTooltip('Переименовать'), findsOneWidget);
    expect(find.text('Удалить'), findsNothing);
  });

  testWidgets(
    'solo owner sees Invite and Join',
    skip: !anonymous,
    (tester) async {
    await tester.pumpWidget(
      _app(
        DeviceListResult(
          activeCount: 1,
          maxDevices: 5,
          devices: [_slot(id: 1, current: true, owner: true)],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Добавить устройство в подписку'), findsOneWidget);
    expect(find.text('Войти в группу'), findsOneWidget);
    expect(find.text('Покинуть чужую подписку'), findsNothing);
    expect(find.text('Выйти на всех устройствах'), findsOneWidget);
  });

  testWidgets(
    'owner with others hides Join and can revoke',
    skip: !anonymous,
    (tester) async {
    await tester.pumpWidget(
      _app(
        DeviceListResult(
          activeCount: 2,
          maxDevices: 5,
          devices: [
            _slot(id: 1, current: true, owner: true, name: 'Pixel'),
            _slot(id: 2, current: false, owner: false, name: 'iPhone'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Добавить устройство в подписку'), findsOneWidget);
    expect(find.text('Войти в группу'), findsNothing);
    expect(find.text('Выйти на всех устройствах'), findsOneWidget);
    expect(find.text('Это устройство'), findsOneWidget);
    expect(find.text('Удалить'), findsOneWidget);
    expect(find.byTooltip('Переименовать'), findsNWidgets(2));
    expect(find.text('iPhone'), findsOneWidget);
  });

  testWidgets(
    'member with others leaves, does not revoke',
    skip: !anonymous,
    (tester) async {
    await tester.pumpWidget(
      _app(
        DeviceListResult(
          activeCount: 2,
          maxDevices: 5,
          devices: [
            _slot(id: 1, current: true, owner: false, name: 'Windows'),
            _slot(id: 2, current: false, owner: true, name: 'Pixel'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Это устройство'), findsOneWidget);
    expect(find.text('Удалить'), findsNothing);
    expect(find.text('Покинуть чужую подписку'), findsOneWidget);
    expect(find.text('Pixel'), findsOneWidget);
  });
}
