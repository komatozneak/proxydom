import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teremok_connect/core/widgets/location_flag_icon.dart';
import 'package:teremok_connect/core/widgets/signal_nest_hero.dart';
import 'package:teremok_connect/features/home/application/vpn_provider.dart';
import 'package:teremok_connect/features/home/application/vpn_status.dart';
import 'package:teremok_connect/features/home/presentation/home_screen.dart';
import 'package:teremok_connect/features/home/presentation/widgets/free_quota_bar.dart';
import 'package:teremok_connect/features/home/presentation/widgets/server_card.dart';
import 'package:teremok_connect/features/settings/application/subscription_status_provider.dart';
import 'package:teremok_connect/features/settings/data/subscription_status.dart';
import 'package:teremok_connect/features/vpn/data/node_display.dart';
import 'package:teremok_connect/features/vpn/data/vpn_node.dart';
import 'package:teremok_connect/features/vpn/data/vpn_nodes_repository.dart';
import 'package:teremok_connect/l10n/app_localizations.dart';

class _FakeVpnNodesRepository extends VpnNodesRepository {
  _FakeVpnNodesRepository(this.nodes);

  final List<VpnNode> nodes;

  @override
  Future<List<VpnNode>> listNodes({bool allowCacheFallback = true}) async =>
      nodes;

  @override
  Future<({List<VpnNode> nodes, bool fromCache})> listNodesDetailed({
    bool allowCacheFallback = true,
  }) async =>
      (nodes: nodes, fromCache: false);

  @override
  Future<List<VpnNode>?> loadCachedNodes() async => nodes;

  @override
  Future<String?> getSelectedNodeId() async => kRegionAutoId;
}

class _FixedVpnNotifier extends VpnNotifier {
  _FixedVpnNotifier(
    this._status, {
    this.overrideDisplayLabel,
    this.overrideWinnerId,
  });

  final VpnStatus _status;
  final String? overrideDisplayLabel;
  final String? overrideWinnerId;

  @override
  VpnStatus build() => _status;

  @override
  String? get displayLabel => overrideDisplayLabel ?? super.displayLabel;

  @override
  String? get autoWinnerId => overrideWinnerId;

  @override
  Future<void> syncFromNative() async {}

  @override
  Future<void> onAppResumed() async {}

  @override
  Future<void> reconcileWithNative() async {}
}

class _FixedSubNotifier extends SubscriptionStatusNotifier {
  _FixedSubNotifier(this._status);

  final SubscriptionStatus _status;

  @override
  Future<SubscriptionStatus> build() async => _status;

  @override
  Future<void> refresh() async {
    state = AsyncData(_status);
  }
}

/// Uses real [SubscriptionStatusNotifier.refresh] so layout can stay mounted.
class _HoldRefreshSubNotifier extends SubscriptionStatusNotifier {
  _HoldRefreshSubNotifier(this.current);

  SubscriptionStatus current;
  Completer<SubscriptionStatus>? hold;

  @override
  Future<SubscriptionStatus> build() async => current;

  @override
  Future<SubscriptionStatus> loadFreeQuota() async {
    final pending = hold;
    if (pending != null) return pending.future;
    return current;
  }
}

VpnNode _hy2({
  required String id,
  required String label,
  required String host,
  String? purpose,
  String? region,
}) {
  return VpnNode(
    id: id,
    label: label,
    host: host,
    port: 443,
    status: 'connected',
    isDefault: false,
    protocol: kVpnNodeProtocolHysteria2,
    purpose: purpose,
    region: region,
  );
}

const _freeQuota = SubscriptionStatus(
  quotaBytesLimit: 1 << 32,
  quotaBytesRemaining: 1 << 31,
  quotaBytesUsed: 1 << 31,
);

void _mockVpnChannel() {
  const vpnChannel = MethodChannel('teremok/vpn');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(vpnChannel, (call) async {
    if (call.method == 'getStatus') return 'idle';
    if (call.method == 'getLastError') return '';
    return null;
  });
}

List<VpnNode> get _euUsPool => [
      _hy2(
        id: 'eu-hy2-1',
        label: 'Европа · Бесплатно',
        host: '217.60.3.9',
        region: 'eu',
      ),
      _hy2(
        id: 'us-hy2-1',
        label: 'США · Бесплатно',
        host: '45.91.248.91',
        purpose: 'geo-us',
      ),
    ];

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
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _mockVpnChannel();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('teremok/vpn'), null);
  });

  test('location blurbs hide protocol names', () {
    final en = lookupAppL10n(const Locale('en'));
    final ru = lookupAppL10n(const Locale('ru'));
    expect(ru.regionAutoSubtitle, 'Ближайшая локация');
    expect(ru.regionAutoSubtitle, isNot(contains('свободная')));
    for (final s in [
      en.regionBlurbFree,
      en.regionBlurbGaming,
      en.regionBlurbYoutube,
      en.regionBlurbIndia,
      en.regionAutoSubtitle,
      ru.regionBlurbFree,
      ru.regionBlurbGaming,
      ru.regionBlurbYoutube,
      ru.regionBlurbIndia,
      ru.regionAutoSubtitle,
    ]) {
      expect(s.toLowerCase(), isNot(contains('hysteria')));
      expect(s.toLowerCase(), isNot(contains('hy2')));
      expect(s.toLowerCase(), isNot(contains('trusttunnel')));
    }
    expect(en.regionBlurbYoutube.toLowerCase(), isNot(contains('youtube')));
    expect(ru.regionBlurbYoutube.toLowerCase(), isNot(contains('youtube')));
    expect(en.regionBlurbYoutube.toLowerCase(), isNot(contains('without ads')));
    expect(ru.regionBlurbYoutube, isNot(contains('реклам')));
    expect(en.regionBlurbIndia.toLowerCase(), isNot(contains('prices')));
    expect(ru.regionBlurbIndia, isNot(contains('цен')));
  });

  test('sanitizeHomeLabel strips Premium suffix like Locations titles', () {
    expect(sanitizeHomeLabel('YouTube · Premium'), 'YouTube');
    expect(sanitizeHomeLabel('Игровой · Premium'), 'Игровой');
    expect(
        placeForNode(
          const VpnNode(
            id: 'al-youtube',
            label: 'YouTube · Premium',
            host: '85.155.228.235',
            port: 443,
            status: 'connected',
            isDefault: false,
            purpose: 'youtube',
            protocol: 'trusttunnel',
            requiresPremium: true,
          ),
        ).title,
        'YouTube');
  });

  testWidgets('Free quota meter sits above Nest with unlimited curtain',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final container = ProviderContainer(
      overrides: [
        vpnNodesRepositoryProvider.overrideWithValue(
          _FakeVpnNodesRepository(_euUsPool),
        ),
        vpnProvider.overrideWith(
          () => _FixedVpnNotifier(const VpnDisconnected()),
        ),
        subscriptionStatusProvider.overrideWith(
          () => _FixedSubNotifier(_freeQuota),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester
        .pumpWidget(_app(container: container, home: const HomeScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(kHomeQuotaBarKey), findsOneWidget);
    expect(find.byType(FreeQuotaBar), findsOneWidget);
    expect(find.text('Безлимит с Premium'), findsNothing);
    expect(find.text('Подключить безлимит'), findsNothing);
    expect(find.byType(SignalNestHero), findsOneWidget);

    final quotaY = tester.getTopLeft(find.byKey(kHomeQuotaBarKey)).dy;
    final nestY = tester.getTopLeft(find.byKey(kHomeSignalNestKey)).dy;
    expect(quotaY, lessThan(nestY));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('iOS Free quota meter has no Premium curtain or NoVPN row',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });
    final container = ProviderContainer(
      overrides: [
        vpnNodesRepositoryProvider.overrideWithValue(
          _FakeVpnNodesRepository(_euUsPool),
        ),
        vpnProvider.overrideWith(
          () => _FixedVpnNotifier(const VpnDisconnected()),
        ),
        subscriptionStatusProvider.overrideWith(
          () => _FixedSubNotifier(_freeQuota),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester
        .pumpWidget(_app(container: container, home: const HomeScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(kHomeSignalNestKey), findsOneWidget);
    expect(find.byKey(kHomeQuotaBarKey), findsNothing);
    expect(find.text('Нажмите для подключения'), findsOneWidget);
    expect(find.text('Нет серверов'), findsOneWidget);
    expect(find.text('Безлимит с Premium'), findsNothing);
    expect(find.text('Что работает без VPN?'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('quota bar stays mounted and does not jump during refresh',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final notifier = _HoldRefreshSubNotifier(_freeQuota);
    final container = ProviderContainer(
      overrides: [
        vpnNodesRepositoryProvider.overrideWithValue(
          _FakeVpnNodesRepository(_euUsPool),
        ),
        vpnProvider.overrideWith(
          () => _FixedVpnNotifier(const VpnDisconnected()),
        ),
        subscriptionStatusProvider.overrideWith(() => notifier),
      ],
    );
    addTearDown(container.dispose);

    await tester
        .pumpWidget(_app(container: container, home: const HomeScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(kHomeQuotaBarKey), findsOneWidget);
    final yBefore = tester.getTopLeft(find.byKey(kHomeQuotaBarKey)).dy;

    notifier.hold = Completer<SubscriptionStatus>();
    final refresh =
        container.read(subscriptionStatusProvider.notifier).refresh();
    await tester.pump();
    expect(find.byKey(kHomeQuotaBarKey), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(kHomeQuotaBarKey)).dy, yBefore);

    notifier.hold!.complete(_freeQuota);
    await refresh;
    await tester.pump();
    expect(find.byKey(kHomeQuotaBarKey), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(kHomeQuotaBarKey)).dy, yBefore);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('quota curtain tap opens paste link', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const HomeScreen(),
        ),
        GoRoute(
          path: '/import',
          builder: (_, __) => const Scaffold(body: Text('IMPORT_LINK')),
        ),
        GoRoute(
          path: '/subscription',
          builder: (_, __) => const Scaffold(body: Text('SUB_PAGE')),
        ),
        GoRoute(
          path: '/locations',
          builder: (_, __) => const Scaffold(body: Text('LOC')),
        ),
        GoRoute(
          path: '/settings/no-vpn',
          builder: (_, __) => const Scaffold(body: Text('NOVPN')),
        ),
      ],
    );
    addTearDown(router.dispose);

    final container = ProviderContainer(
      overrides: [
        vpnNodesRepositoryProvider.overrideWithValue(
          _FakeVpnNodesRepository(_euUsPool),
        ),
        vpnProvider.overrideWith(
          () => _FixedVpnNotifier(const VpnDisconnected()),
        ),
        subscriptionStatusProvider.overrideWith(
          () => _FixedSubNotifier(_freeQuota),
        ),
      ],
    );
    addTearDown(container.dispose);

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
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byKey(kHomeQuotaBarKey));
    await tester.pumpAndSettle();
    expect(find.text('IMPORT_LINK'), findsOneWidget);
    expect(find.text('SUB_PAGE'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('iOS quota bar tap opens paste link, not /subscription',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const HomeScreen(),
        ),
        GoRoute(
          path: '/subscription',
          builder: (_, __) => const Scaffold(body: Text('SUB_PAGE')),
        ),
        GoRoute(
          path: '/settings/account',
          builder: (_, __) => const Scaffold(body: Text('ACCOUNT_HUB')),
        ),
        GoRoute(
          path: '/import',
          builder: (_, __) => const Scaffold(body: Text('IMPORT_LINK')),
        ),
        GoRoute(
          path: '/locations',
          builder: (_, __) => const Scaffold(body: Text('LOC')),
        ),
        GoRoute(
          path: '/settings/no-vpn',
          builder: (_, __) => const Scaffold(body: Text('NOVPN')),
        ),
      ],
    );
    addTearDown(router.dispose);

    final container = ProviderContainer(
      overrides: [
        vpnNodesRepositoryProvider.overrideWithValue(
          _FakeVpnNodesRepository(_euUsPool),
        ),
        vpnProvider.overrideWith(
          () => _FixedVpnNotifier(const VpnDisconnected()),
        ),
        subscriptionStatusProvider.overrideWith(
          () => _FixedSubNotifier(_freeQuota),
        ),
      ],
    );
    addTearDown(container.dispose);

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
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Подключить безлимит'), findsNothing);
    await tester.tap(find.text('Вставить'));
    await tester.pumpAndSettle();
    expect(find.text('IMPORT_LINK'), findsOneWidget);
    expect(find.text('Сначала подключитесь.'), findsNothing);
    expect(find.text('ACCOUNT_HUB'), findsNothing);
    expect(find.text('SUB_PAGE'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('iOS quota exceeded CTA opens paste link, not Оформить Premium',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const HomeScreen(),
        ),
        GoRoute(
          path: '/locked',
          builder: (_, __) => const Scaffold(body: Text('LOCKED')),
        ),
        GoRoute(
          path: '/settings/account',
          builder: (_, __) => const Scaffold(body: Text('ACCOUNT_HUB')),
        ),
        GoRoute(
          path: '/import',
          builder: (_, __) => const Scaffold(body: Text('IMPORT_LINK')),
        ),
        GoRoute(
          path: '/locations',
          builder: (_, __) => const Scaffold(body: Text('LOC')),
        ),
        GoRoute(
          path: '/settings/no-vpn',
          builder: (_, __) => const Scaffold(body: Text('NOVPN')),
        ),
      ],
    );
    addTearDown(router.dispose);

    final container = ProviderContainer(
      overrides: [
        vpnNodesRepositoryProvider.overrideWithValue(
          _FakeVpnNodesRepository(_euUsPool),
        ),
        vpnProvider.overrideWith(
          () => _FixedVpnNotifier(
            const VpnError(message: 'quota', code: 'quota_exceeded'),
          ),
        ),
        subscriptionStatusProvider.overrideWith(
          () => _FixedSubNotifier(_freeQuota),
        ),
      ],
    );
    addTearDown(container.dispose);

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
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Оформить Premium'), findsNothing);
    expect(find.textContaining('Оформите Premium'), findsNothing);
    await tester.tap(find.text('Вставить'));
    await tester.pumpAndSettle();
    expect(find.text('IMPORT_LINK'), findsOneWidget);
    expect(find.text('Сначала подключитесь.'), findsNothing);
    expect(find.text('ACCOUNT_HUB'), findsNothing);
    expect(find.text('LOCKED'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('two fast taps open one paste screen', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');
    final router = GoRouter(
      navigatorKey: rootKey,
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/import',
          parentNavigatorKey: rootKey,
          builder: (_, __) => const Scaffold(body: Text('IMPORT_LINK')),
        ),
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) {
            return Scaffold(body: navigationShell);
          },
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/locations',
                  builder: (_, __) => const Scaffold(body: Text('LOC')),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/home',
                  builder: (_, __) => const HomeScreen(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/settings',
                  builder: (_, __) => const Scaffold(body: Text('SET')),
                  routes: [
                    GoRoute(
                      path: 'no-vpn',
                      builder: (_, __) => const Scaffold(body: Text('NOVPN')),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    final container = ProviderContainer(
      overrides: [
        vpnNodesRepositoryProvider.overrideWithValue(
          _FakeVpnNodesRepository(_euUsPool),
        ),
        vpnProvider.overrideWith(
          () => _FixedVpnNotifier(const VpnDisconnected()),
        ),
        subscriptionStatusProvider.overrideWith(
          () => _FixedSubNotifier(_freeQuota),
        ),
      ],
    );
    addTearDown(container.dispose);

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
    await tester.pump(const Duration(milliseconds: 400));

    expect(router.routerDelegate.currentConfiguration.uri.path, '/home');
    expect(find.byKey(kHomeQuotaBarKey), findsOneWidget);

    final bar = tester.widget<FreeQuotaBar>(find.byType(FreeQuotaBar));
    bar.onTap!.call();
    bar.onTap!.call();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Duplicate push would assert on page keys (!keyReservation.contains).
    expect(tester.takeException(), isNull);
    expect(find.text('IMPORT_LINK', skipOffstage: false), findsOneWidget);
    expect(find.byType(HomeScreen, skipOffstage: false), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Auto connecting cycles Free pool flags LV then US',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final container = ProviderContainer(
      overrides: [
        vpnNodesRepositoryProvider.overrideWithValue(
          _FakeVpnNodesRepository(_euUsPool),
        ),
        vpnProvider.overrideWith(
          () => _FixedVpnNotifier(const VpnConnecting(progress: 0.4)),
        ),
        subscriptionStatusProvider.overrideWith(
          () => _FixedSubNotifier(_freeQuota),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester
        .pumpWidget(_app(container: container, home: const HomeScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(ServerCard), findsOneWidget);
    expect(find.text('🌐'), findsNothing);
    expect(find.text('Автоматически'), findsOneWidget);
    expect(find.text('Ближайшая локация'), findsOneWidget);
    expect(find.text('Европа'), findsNothing);

    final first = tester
        .widget<LocationFlagIcon>(
          find.descendant(
            of: find.byType(ServerCard),
            matching: find.byType(LocationFlagIcon),
          ),
        )
        .flag;
    expect(first, kFlagEurope);
    expect(find.text('Автоматически'), findsOneWidget);
    expect(find.text('Европа'), findsNothing);

    await tester.pump(kAutoFlagCycleDuration);
    await tester.pump();
    final second = tester
        .widgetList<LocationFlagIcon>(
          find.descendant(
            of: find.byType(ServerCard),
            matching: find.byType(LocationFlagIcon),
          ),
        )
        .last
        .flag;
    expect(second, kFlagUsa);
    expect(find.text('Автоматически'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Home ServerCard strips · Premium like Locations titles',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const yt = VpnNode(
      id: 'al-youtube',
      label: 'YouTube · Premium',
      host: '85.155.228.235',
      port: 443,
      status: 'connected',
      isDefault: false,
      protocol: 'trusttunnel',
      purpose: 'youtube',
      requiresPremium: true,
    );
    final container = ProviderContainer(
      overrides: [
        vpnNodesRepositoryProvider.overrideWithValue(
          _FakeVpnNodesRepository([..._euUsPool, yt]),
        ),
        vpnProvider.overrideWith(
          () => _FixedVpnNotifier(
            VpnConnected(
              serverName: 'YouTube · Premium',
              protocol: 'TrustTunnel',
              connectedSince: DateTime.now(),
            ),
            overrideDisplayLabel: 'YouTube · Premium',
            overrideWinnerId: 'al-youtube',
          ),
        ),
        subscriptionStatusProvider.overrideWith(
          () => _FixedSubNotifier(
            const SubscriptionStatus(isPro: true),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester
        .pumpWidget(_app(container: container, home: const HomeScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('YouTube'), findsWidgets);
    expect(find.textContaining('· Premium'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Auto connected winner shows Locations title, not Европа · Авто',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final container = ProviderContainer(
      overrides: [
        vpnNodesRepositoryProvider.overrideWithValue(
          _FakeVpnNodesRepository(_euUsPool),
        ),
        vpnProvider.overrideWith(
          () => _FixedVpnNotifier(
            VpnConnected(
              serverName: 'Европа · Бесплатно',
              protocol: 'Hysteria2',
              connectedSince: DateTime.now(),
            ),
            overrideDisplayLabel: 'Европа · Бесплатно',
            overrideWinnerId: 'eu-hy2-1',
          ),
        ),
        subscriptionStatusProvider.overrideWith(
          () => _FixedSubNotifier(_freeQuota),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester
        .pumpWidget(_app(container: container, home: const HomeScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Латвия'), findsOneWidget);
    expect(find.text('Низкий пинг'), findsOneWidget);
    expect(find.text('Европа'), findsNothing);
    expect(find.textContaining('Авто'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('connecting hint uses canonical location title', (tester) async {
    final container = ProviderContainer(
      overrides: [
        vpnNodesRepositoryProvider.overrideWithValue(
          _FakeVpnNodesRepository(_euUsPool),
        ),
        vpnProvider.overrideWith(
          () => _FixedVpnNotifier(
            const VpnConnecting(
              progress: 0.55,
              hint: 'Подбираем сервер… Латвия',
            ),
          ),
        ),
        subscriptionStatusProvider.overrideWith(
          () => _FixedSubNotifier(_freeQuota),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester
        .pumpWidget(_app(container: container, home: const HomeScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Подбираем сервер… Латвия'), findsOneWidget);
    expect(find.textContaining('Европа'), findsNothing);
  });
}
