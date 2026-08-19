import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teremok_connect/core/theme.dart';
import 'package:teremok_connect/features/home/application/vpn_provider.dart';
import 'package:teremok_connect/features/home/application/vpn_status.dart';
import 'package:teremok_connect/features/home/presentation/home_screen.dart';
import 'package:teremok_connect/features/vpn/data/vpn_controller.dart';
import 'package:teremok_connect/features/vpn/data/vpn_node.dart';
import 'package:teremok_connect/features/vpn/data/vpn_nodes_repository.dart';
import 'package:teremok_connect/features/vpn/domain/vpn_connect_error.dart';
import 'package:teremok_connect/l10n/app_localizations.dart';

class _FakeVpnNodesRepository extends VpnNodesRepository {
  @override
  Future<List<VpnNode>> listNodes({bool allowCacheFallback = true}) async =>
      const [];

  @override
  Future<({List<VpnNode> nodes, bool fromCache})> listNodesDetailed({
    bool allowCacheFallback = true,
  }) async =>
      (nodes: <VpnNode>[], fromCache: false);

  @override
  Future<String?> getSelectedNodeId() async => null;
}

class _FixedVpnNotifier extends VpnNotifier {
  _FixedVpnNotifier(this._status);

  final VpnStatus _status;

  @override
  VpnStatus build() => _status;
}

class _CancelTrackingNotifier extends VpnNotifier {
  _CancelTrackingNotifier(this._status);

  final VpnStatus _status;
  int disconnectCalls = 0;

  @override
  VpnStatus build() => _status;

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VpnConflictInfo.fromNative', () {
    test('marks foreign Always-on as blocking', () {
      final info = VpnConflictInfo.fromNative({
        'foreignAlwaysOn': true,
        'packageName': 'com.ogonconnect.app',
        'appLabel': 'Огонь',
        'lockdown': true,
      });
      expect(info.foreignAlwaysOn, isTrue);
      expect(info.displayName, 'Огонь');
    });

    test('treats lockdown-without-pkg as blocking', () {
      final info = VpnConflictInfo.fromNative({
        'foreignAlwaysOn': false,
        'lockdown': true,
      });
      expect(info.foreignAlwaysOn, isTrue);
    });

    test('returns none when not blocking', () {
      final info = VpnConflictInfo.fromNative({
        'foreignAlwaysOn': false,
        'lockdown': false,
      });
      expect(info.foreignAlwaysOn, isFalse);
      expect(identical(info, VpnConflictInfo.none) || !info.foreignAlwaysOn,
          isTrue);
    });
  });

  testWidgets('Home shows conflict title, hint and Open VPN settings CTA',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vpnNodesRepositoryProvider
              .overrideWithValue(_FakeVpnNodesRepository()),
          vpnProvider.overrideWith(
            () => _FixedVpnNotifier(
              const VpnError(
                message: 'Огонь',
                code: kVpnConflictErrorCode,
              ),
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          locale: const Locale('ru'),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Мешает другой VPN'), findsOneWidget);
    expect(
      find.textContaining('Огонь'),
      findsWidgets,
    );
    expect(find.text('Открыть настройки VPN'), findsOneWidget);
    expect(
        find.text('Не удалось подключиться. Попробуйте снова.'), findsNothing);
  });

  testWidgets('Home shows permission hint without VPN settings CTA',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vpnNodesRepositoryProvider
              .overrideWithValue(_FakeVpnNodesRepository()),
          vpnProvider.overrideWith(
            () => _FixedVpnNotifier(
              const VpnError(
                message: 'VPN permission denied',
                code: 'permission_denied',
              ),
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          locale: const Locale('ru'),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Ошибка подключения'), findsOneWidget);
    expect(find.textContaining('Разрешите VPN'), findsOneWidget);
    expect(find.text('Открыть настройки VPN'), findsNothing);
  });

  testWidgets('Home shows path_incompatible hint, not generic friendly error',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vpnNodesRepositoryProvider
              .overrideWithValue(_FakeVpnNodesRepository()),
          vpnProvider.overrideWith(
            () => _FixedVpnNotifier(
              const VpnError(
                message: kVpnPathIncompatibleErrorCode,
                code: kVpnPathIncompatibleErrorCode,
              ),
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          locale: const Locale('ru'),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Ошибка подключения'), findsOneWidget);
    expect(
      find.text(
        'Не вышло проверить сервер. Нажмите ещё раз или выберите локацию вручную.',
      ),
      findsOneWidget,
    );
    expect(
        find.text('Не удалось подключиться. Попробуйте снова.'), findsNothing);
  });

  testWidgets('Nest tap while Connecting cancels the walk', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final notifier = _CancelTrackingNotifier(
      const VpnConnecting(progress: 0.55, hint: 'Латвия'),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vpnNodesRepositoryProvider
              .overrideWithValue(_FakeVpnNodesRepository()),
          vpnProvider.overrideWith(() => notifier),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          locale: const Locale('ru'),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byKey(kHomeSignalNestKey));
    await tester.pump();

    expect(notifier.disconnectCalls, 1);
  });
}
