import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/core/theme.dart';
import 'package:teremok_connect/core/widgets/location_flag_icon.dart';
import 'package:teremok_connect/features/home/application/vpn_provider.dart';
import 'package:teremok_connect/features/home/application/vpn_status.dart';
import 'package:teremok_connect/features/home/presentation/widgets/server_card.dart';
import 'package:teremok_connect/l10n/app_localizations.dart';

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
}
