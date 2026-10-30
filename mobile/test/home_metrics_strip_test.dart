// Home's session strip prints readings, never placeholders.
//
// It used to reserve a column for every metric and fill the empty ones with an
// em dash, so an idle screen read «Время — · Пинг — · Трафик 86 ГБ» and a local
// key read «Трафик —». A dash is a broken gauge to the eye: the strip now draws
// a column only when it has a value, and a ping that has not answered yet is an
// ellipsis, not a minus.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/core/theme.dart';
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
}

VpnConnected _connected() => VpnConnected(
      serverName: 'Игровой',
      protocol: 'hysteria2',
      connectedSince: DateTime.now().subtract(const Duration(minutes: 12)),
    );

/// One saved profile: a saved line is what makes Home draw its strip.
void _seedProfile({bool withTraffic = true}) {
  SharedPreferences.setMockInitialValues({
    'hy2_import_v1': jsonEncode({
      'catalogs': [
        {
          'id': 'profile',
          'title': 'Мой профиль',
          // 15 GiB up + 31 GiB down of a 200 GB cap ≈ 143 GiB left.
          if (withTraffic)
            'trafficMeta':
                'upload=15000000000; download=31000000000; total=200000000000',
          'lines': [
            'hysteria2://pw@eu1.proxydom.su:443?sni=eu1.proxydom.su&insecure=1'
                '#%D0%98%D0%B3%D1%80%D0%BE%D0%B2%D0%BE%D0%B9',
          ],
        },
      ],
      'selected': 0,
    }),
  });
}

Future<void> _pumpHome(
  WidgetTester tester, {
  required VpnStatus status,
  required TargetPlatform platform,
  Stream<int?>? nativePing,
  bool withTraffic = true,
  Size logicalSize = const Size(900, 700),
  double dpr = 1,
}) async {
  debugDefaultTargetPlatformOverride = platform;
  _seedProfile(withTraffic: withTraffic);

  tester.view
    ..physicalSize = logicalSize * dpr
    ..devicePixelRatio = dpr;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        vpnProvider.overrideWith(() => _ScriptedVpn(status)),
        // Never touch the platform channel from a widget test.
        vpnPingStreamProvider.overrideWithValue(
          nativePing ?? Stream<int?>.value(null),
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
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
}

/// Every em dash on Home is a bug now.
Finder get _anyDash => find.text('—');

Finder _clock() => find.byWidgetPredicate(
      (widget) =>
          widget is Text &&
          RegExp(r'^\d{2}:\d{2}:\d{2}$').hasMatch(widget.data ?? ''),
    );

void main() {
  testWidgets('an idle Home is a traffic gauge, not a row of dashes',
      (tester) async {
    await _pumpHome(
      tester,
      status: const VpnDisconnected(),
      platform: TargetPlatform.android,
    );

    // Only what the document states: the cap it was given and how much is
    // left. The clock and the ping belong to a session that is not running.
    expect(find.text('ТРАФИК'), findsOneWidget);
    expect(find.text('143 ГБ'), findsOneWidget);
    expect(find.text('ВРЕМЯ'), findsNothing);
    expect(find.text('ПИНГ'), findsNothing);
    expect(_anyDash, findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('with nothing to measure the strip is not on the screen',
      (tester) async {
    await _pumpHome(
      tester,
      status: const VpnDisconnected(),
      platform: TargetPlatform.android,
      withTraffic: false,
    );

    // No session and no document cap: there is no reading at all, so there is
    // no plate holding empty columns.
    expect(find.text('ТРАФИК'), findsNothing);
    expect(find.text('ВРЕМЯ'), findsNothing);
    expect(find.text('ПИНГ'), findsNothing);
    expect(_anyDash, findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a live session reads clock, ping and gauge', (tester) async {
    await _pumpHome(
      tester,
      status: _connected(),
      platform: TargetPlatform.android,
      nativePing: Stream<int?>.value(42),
    );

    expect(find.text('ВРЕМЯ'), findsOneWidget);
    expect(_clock(), findsOneWidget);
    expect(find.text('ПИНГ'), findsOneWidget);
    expect(find.text('42 мс'), findsOneWidget);
    expect(find.text('ТРАФИК'), findsOneWidget);
    expect(find.text('143 ГБ'), findsOneWidget);
    expect(_anyDash, findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a ping that has not answered yet is an ellipsis',
      (tester) async {
    final semantics = tester.ensureSemantics();

    await _pumpHome(
      tester,
      status: _connected(),
      platform: TargetPlatform.android,
      nativePing: Stream<int?>.value(null),
    );

    expect(find.text('…'), findsOneWidget);
    expect(_anyDash, findsNothing);
    expect(find.bySemanticsLabel('Пинг: измеряем'), findsOneWidget);
    semantics.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a document without a cap prints no traffic column',
      (tester) async {
    await _pumpHome(
      tester,
      status: _connected(),
      platform: TargetPlatform.android,
      nativePing: Stream<int?>.value(42),
      withTraffic: false,
    );

    expect(find.text('ТРАФИК'), findsNothing);
    expect(find.text('ПИНГ'), findsOneWidget);
    expect(find.text('42 мс'), findsOneWidget);
    expect(_anyDash, findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('iOS has no probe and prints no speed readout', (tester) async {
    await _pumpHome(
      tester,
      status: _connected(),
      platform: TargetPlatform.iOS,
    );

    expect(find.text('ПИНГ'), findsNothing);
    expect(find.text('Скорость'), findsNothing);
    expect(find.text('ВРЕМЯ'), findsOneWidget);
    expect(find.text('ТРАФИК'), findsOneWidget);
    expect(_anyDash, findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a four-digit sample still fits a phone column', (tester) async {
    await _pumpHome(
      tester,
      status: _connected(),
      platform: TargetPlatform.android,
      nativePing: Stream<int?>.value(1234),
      logicalSize: const Size(360, 780),
      dpr: 3,
    );

    // 1234 ms is written with a non-breaking thousands gap, as on Windows.
    expect(find.text('1\u00A0234 мс'), findsOneWidget);
    // The strip is the tightest row on Home: a wider reading must not overflow
    // the three columns.
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });
}
