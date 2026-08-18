import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teremok_connect/core/widgets/location_flag_icon.dart';
import 'package:teremok_connect/features/home/application/vpn_provider.dart';
import 'package:teremok_connect/features/home/application/vpn_status.dart';
import 'package:teremok_connect/features/home/presentation/home_screen.dart';
import 'package:teremok_connect/features/home/presentation/widgets/server_card.dart';
import 'package:teremok_connect/features/settings/application/subscription_status_provider.dart';
import 'package:teremok_connect/features/settings/data/subscription_status.dart';
import 'package:teremok_connect/features/vpn/data/node_display.dart';
import 'package:teremok_connect/features/vpn/data/vpn_node.dart';
import 'package:teremok_connect/features/vpn/data/vpn_nodes_repository.dart';
import 'package:teremok_connect/features/vpn/presentation/locations_screen.dart';
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
    this.overrideWinnerId,
  });

  final VpnStatus _status;
  final String? overrideWinnerId;

  @override
  VpnStatus build() => _status;

  @override
  String? get autoWinnerId => overrideWinnerId;

  @override
  Future<void> syncFromNative() async {}

  @override
  Future<void> onAppResumed() async {}
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

VpnNode _hy2({
  required String id,
  required String label,
  required String host,
  String? purpose,
  String? region,
  bool requiresPremium = false,
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
    requiresPremium: requiresPremium,
  );
}

List<VpnNode> get _catalog => [
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
      _hy2(
        id: 'al-youtube',
        label: 'YouTube · Premium',
        host: '85.155.228.235',
        purpose: 'youtube',
        requiresPremium: true,
      ),
    ];

void _mockVpnChannel() {
  const vpnChannel = MethodChannel('teremok/vpn');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(vpnChannel, (call) async {
    if (call.method == 'getStatus') return 'idle';
    if (call.method == 'getLastError') return '';
    return null;
  });
}

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

  testWidgets('Auto YouTube winner matches Home and Locations while connecting',
      (tester) async {
    final container = ProviderContainer(
      overrides: [
        vpnNodesRepositoryProvider.overrideWithValue(
          _FakeVpnNodesRepository(_catalog),
        ),
        vpnProvider.overrideWith(
          () => _FixedVpnNotifier(
            const VpnConnecting(
              progress: 0.75,
              hint: 'YouTube',
            ),
            overrideWinnerId: 'al-youtube',
          ),
        ),
        subscriptionStatusProvider.overrideWith(
          () => _FixedSubNotifier(const SubscriptionStatus(isPro: true)),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester
        .pumpWidget(_app(container: container, home: const HomeScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final homeFlag = tester
        .widget<LocationFlagIcon>(
          find.descendant(
            of: find.byType(ServerCard),
            matching: find.byType(LocationFlagIcon),
          ),
        )
        .flag;
    expect(homeFlag, 'youtube');

    await tester.pumpWidget(
      _app(container: container, home: const LocationsScreen()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Автоматически'), findsOneWidget);
    final locationsFlag =
        tester.widget<LocationFlagIcon>(find.byKey(kLocationsAutoFlagKey)).flag;
    expect(locationsFlag, 'youtube');
    expect(locationsFlag, homeFlag);
  });

  testWidgets('Auto row matches Home fallback before a winner exists',
      (tester) async {
    final container = ProviderContainer(
      overrides: [
        vpnNodesRepositoryProvider.overrideWithValue(
          _FakeVpnNodesRepository(_catalog),
        ),
        vpnProvider.overrideWith(
          () => _FixedVpnNotifier(const VpnDisconnected()),
        ),
        subscriptionStatusProvider.overrideWith(
          () => _FixedSubNotifier(
            const SubscriptionStatus(
              quotaBytesLimit: 1 << 32,
              quotaBytesRemaining: 1 << 31,
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester
        .pumpWidget(_app(container: container, home: const HomeScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final homeFlag = tester
        .widget<LocationFlagIcon>(
          find.descendant(
            of: find.byType(ServerCard),
            matching: find.byType(LocationFlagIcon),
          ),
        )
        .flag;

    await tester.pumpWidget(
      _app(container: container, home: const LocationsScreen()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final locationsFlag =
        tester.widget<LocationFlagIcon>(find.byKey(kLocationsAutoFlagKey)).flag;
    expect(locationsFlag, homeFlag);
    expect(locationsFlag, kFlagEurope);
  });
}
