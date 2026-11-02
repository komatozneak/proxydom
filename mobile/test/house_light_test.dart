// A server pick drops the tunnel without pressing the house.
//
// The status word follows the tunnel immediately, and the house follows it:
// the firefly circle is the tunnel's state, not the finger's. It used to stay
// because a fully lit house was treated as something the listener must not
// touch, and the lamp flag was only cleared by the press timer.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/core/theme.dart';
import 'package:proxydom/core/widgets/connect_button.dart';
import 'package:proxydom/core/widgets/pixel_house_hero.dart';
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
  testWidgets('the house goes out when a server switch drops the tunnel',
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

    expect(
      tester.widget<PixelHouseHero>(find.byType(PixelHouseHero)).state,
      TreeState.connected,
    );

    vpn.show(const VpnDisconnected());
    await tester.pump();

    expect(find.text('Не подключено'), findsOneWidget);
    expect(
      tester.widget<PixelHouseHero>(find.byType(PixelHouseHero)).state,
      TreeState.disconnected,
    );

    debugDefaultTargetPlatformOverride = null;
  });
}
