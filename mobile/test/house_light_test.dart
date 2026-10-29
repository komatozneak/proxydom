// A server pick drops the tunnel without pressing the house.
//
// The status word follows the tunnel immediately. The rings used to stay,
// because a fully lit yard was treated as something the listener must not
// touch, and the lamp flag was only cleared by the press timer.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/core/theme.dart';
import 'package:proxydom/core/widgets/house_orbit.dart';
import 'package:proxydom/core/widgets/house_pulsar.dart';
import 'package:proxydom/features/home/application/home_stats_provider.dart';
import 'package:proxydom/features/home/application/vpn_provider.dart';
import 'package:proxydom/features/home/application/vpn_status.dart';
import 'package:proxydom/features/home/presentation/home_screen.dart';
import 'package:proxydom/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ScriptedVpn extends VpnNotifier {
  _ScriptedVpn(this._initial);

  final VpnStatus _initial;

  @override
  VpnStatus build() => _initial;

  @override
  Future<void> syncFromNative() async {}

  @override
  Future<void> reconcileWithNative() async {}

  void show(VpnStatus next) => state = next;
}

void main() {
  testWidgets('rings go out when a server switch drops the tunnel',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    SharedPreferences.setMockInitialValues({});

    tester.view
      ..physicalSize = const Size(900, 700)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final vpn = _ScriptedVpn(
      VpnConnected(
        serverName: 'Игровой',
        protocol: 'hysteria2',
        connectedSince: DateTime.utc(2026, 10, 5, 12),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vpnProvider.overrideWith(() => vpn),
          windowsPingSourceProvider.overrideWithValue(
            () => Stream<int?>.value(null),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          locale: const Locale('ru'),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          home: const HomeScreen(),
        ),
      ),
    );
    // The opening frame only schedules the match. The next one paints it.
    await tester.pump();

    expect(find.byType(HousePulsar), findsOneWidget);
    expect(tester.widget<HouseOrbit>(find.byType(HouseOrbit)).burning, 1);

    vpn.show(const VpnDisconnected());
    await tester.pump();

    expect(find.text('Не подключено'), findsOneWidget);
    expect(find.byType(HousePulsar), findsNothing);
    expect(tester.widget<HouseOrbit>(find.byType(HouseOrbit)).burning, 0);

    debugDefaultTargetPlatformOverride = null;
  });
}
