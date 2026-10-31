import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/core/theme.dart';
import 'package:proxydom/core/widgets/location_flag_icon.dart';
import 'package:proxydom/features/home/application/vpn_provider.dart';
import 'package:proxydom/features/home/application/vpn_status.dart';
import 'package:proxydom/features/home/presentation/widgets/server_card.dart';
import 'package:proxydom/features/vpn/data/node_display.dart';
import 'package:proxydom/l10n/app_localizations.dart';

class _FixedVpnNotifier extends VpnNotifier {
  _FixedVpnNotifier(this._status);

  final VpnStatus _status;

  @override
  VpnStatus build() => _status;
}

Widget _wrap(Widget child, {required List<Override> overrides}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: AppTheme.light,
      locale: const Locale('ru'),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

String _cardFlag(WidgetTester tester) {
  return tester
      .widgetList<LocationFlagIcon>(find.byType(LocationFlagIcon))
      .last
      .flag;
}

void main() {
  testWidgets('ServerCard hides session column when disconnected',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        const ServerCard(
          title: 'США',
          subtitle: 'Нью-Йорк',
          flagEmoji: '🇺🇸',
          onTap: null,
        ),
        overrides: [
          vpnProvider.overrideWith(
            () => _FixedVpnNotifier(const VpnDisconnected()),
          ),
        ],
      ),
    );

    expect(find.text('США'), findsOneWidget);
    expect(find.text('Нью-Йорк'), findsOneWidget);
    expect(find.text('СЕССИЯ'), findsNothing);
    expect(find.textContaining('ms'), findsNothing);
    expect(find.byType(LocationFlagIcon), findsOneWidget);
    expect(find.text('🇺🇸'), findsNothing);
  });

  testWidgets('ServerCard shows session timer when connected', (tester) async {
    final since =
        DateTime.now().subtract(const Duration(minutes: 11, seconds: 9));
    await tester.pumpWidget(
      _wrap(
        const ServerCard(
          title: 'США',
          subtitle: 'Нью-Йорк',
          flagEmoji: '🇺🇸',
          onTap: null,
        ),
        overrides: [
          vpnProvider.overrideWith(
            () => _FixedVpnNotifier(
              VpnConnected(
                serverName: 'США',
                protocol: 'VLESS',
                connectedSince: since,
              ),
            ),
          ),
        ],
      ),
    );
    await tester.pump();

    expect(find.text('СЕССИЯ'), findsOneWidget);
    expect(find.text('11:09'), findsOneWidget);
    expect(find.textContaining('ms'), findsNothing);

    final sessionY = tester.getTopLeft(find.text('СЕССИЯ')).dy;
    final timerY = tester.getTopLeft(find.text('11:09')).dy;
    expect(sessionY, lessThan(timerY));
  });

  testWidgets('Auto Connecting cycles Free pool flags LV then US',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        const ServerCard(
          title: 'Автоматически',
          subtitle: 'Ближайшая локация',
          flagEmoji: kFlagEurope,
          selectionIsAuto: true,
          autoPoolFlags: [kFlagEurope, kFlagUsa],
        ),
        overrides: [
          vpnProvider.overrideWith(
            () => _FixedVpnNotifier(const VpnConnecting(progress: 0.4)),
          ),
        ],
      ),
    );
    await tester.pump();
    expect(_cardFlag(tester), kFlagEurope);

    await tester.pump(kAutoFlagCycleDuration);
    await tester.pump();
    expect(_cardFlag(tester), kFlagUsa);
  });

  testWidgets('Auto Connecting cycles category pool through cloud and media',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        const ServerCard(
          title: 'Автоматически',
          subtitle: 'Ближайшая локация',
          flagEmoji: kFlagEurope,
          selectionIsAuto: true,
          autoPoolFlags: [kFlagEurope, kFlagUsa, kFlagCloud, 'media'],
        ),
        overrides: [
          vpnProvider.overrideWith(
            () => _FixedVpnNotifier(const VpnConnecting(progress: 0.4)),
          ),
        ],
      ),
    );
    await tester.pump();
    expect(_cardFlag(tester), kFlagEurope);

    await tester.pump(kAutoFlagCycleDuration);
    await tester.pump();
    expect(_cardFlag(tester), kFlagUsa);
    await tester.pump(kAutoFlagCycleDuration);
    await tester.pump();
    expect(_cardFlag(tester), kFlagCloud);
    await tester.pump(kAutoFlagCycleDuration);
    await tester.pump();
    expect(_cardFlag(tester), 'media');
  });

  testWidgets('Auto Connected keeps the winner flag and does not cycle',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        const ServerCard(
          title: 'Медиа',
          subtitle: '',
          flagEmoji: 'media',
          selectionIsAuto: true,
          autoPoolFlags: [kFlagEurope, kFlagUsa, kFlagCloud, 'media'],
        ),
        overrides: [
          vpnProvider.overrideWith(
            () => _FixedVpnNotifier(
              VpnConnected(
                serverName: 'Медиа',
                protocol: 'hysteria2',
                connectedSince: DateTime.now(),
              ),
            ),
          ),
        ],
      ),
    );
    await tester.pump();
    expect(_cardFlag(tester), 'media');

    await tester.pump(kAutoFlagCycleDuration);
    await tester.pump();
    expect(_cardFlag(tester), 'media');
  });
}
