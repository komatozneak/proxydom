// The refresh key on the Servers tab refreshes the Servers tab.
//
// It came in as «жму обновить — перекидывает в профиль»: the press either did
// nothing at all, or it ran the profile screen's refresh instead of this
// screen's. Both are the same defect from a person's side — the key on this tab
// does not read this tab's documents — so the test pins what makes it honest:
// the press logs under `screen=locations`, and the router stays on
// `/locations`. Leaving for the profile is this screen's answer to a server
// pick; a reload is not a pick.
//
// The screen is driven in the phone layout because that is the one the store
// can be seeded into from a widget test: a window keeps its documents in a
// file, and real file I/O does not run inside the fake-async zone. The window
// drawing of the same key is covered by the two bar tests at the bottom of
// this file, which need no store at all.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:proxydom/core/diagnostics/app_log_buffer.dart';
import 'package:proxydom/core/diagnostics/tunnel_log_level.dart';
import 'package:proxydom/core/theme.dart';
import 'package:proxydom/core/widgets/app_action_button.dart';
import 'package:proxydom/features/vpn/presentation/free_client_chrome.dart';
import 'package:proxydom/features/vpn/presentation/locations_screen.dart';
import 'package:proxydom/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _phone = Size(360, 780);
const _dpr = 3.0;
const _window = Size(1160, 820);

String _line(String name) =>
    'hysteria2://pw@eu1.proxydom.su:443?sni=eu1.proxydom.su&insecure=1#$name';

/// One saved profile with a subscription URL and one pasted key without one —
/// the shape of the owner's own documents.json: two plates on the tab, only one
/// of which has a document behind it.
void _seedDocuments() {
  SharedPreferences.setMockInitialValues({
    'beta_welcome_seen_v1': true,
    'hy2_import_v1': jsonEncode({
      'catalogs': [
        {
          'id': '1790657811181866',
          'title': 'Teremok',
          'url': 'https://sub.proxydom.su/2aq93K0svSy2IRUj',
          'lines': [_line('Москва'), _line('США')],
        },
        {
          'id': 'hy2test',
          'title': 'hy2test',
          'lines': [_line('hy2test')],
        },
      ],
      'selected': 0,
    }),
  });
}

/// A router with the same two paths the app has, so `context.go('/home')` out of
/// the servers tab is observable instead of guessed at.
GoRouter _router() {
  return GoRouter(
    initialLocation: '/locations',
    routes: [
      GoRoute(path: '/locations', builder: (_, __) => const LocationsScreen()),
      GoRoute(
        path: '/home',
        builder: (_, __) => const Scaffold(body: Text('ПРОФИЛЬ')),
      ),
    ],
  );
}

/// The page-level refresh, not the ring on a plate: a full key on a window, a
/// ring beside the QR on a phone.
Finder _barRefresh() {
  return find.descendant(
    of: find.byType(FreeClientActionBar),
    matching: find.byWidgetPredicate((widget) {
      if (widget is AppActionButton) return widget.label == 'Обновить';
      if (widget is AppRingButton) return widget.tooltip == 'Обновить';
      return false;
    }, description: 'the refresh key on the action bar'),
  );
}

Future<GoRouter> _pumpServers(WidgetTester tester) async {
  tester.view
    ..physicalSize = _phone * _dpr
    ..devicePixelRatio = _dpr;
  addTearDown(tester.view.reset);
  final router = _router();
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        routerConfig: router,
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('ru'),
      ),
    ),
  );
  // Boot reads the store, paints the plates and polls the native side.
  for (var i = 0; i < 16; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
  return router;
}

Future<void> _pumpBar(WidgetTester tester, {VoidCallback? onRefresh}) {
  tester.view
    ..physicalSize = _window
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  return tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('ru'),
        home: Scaffold(
          body: FreeClientActionBar(
            onPaste: () {},
            onScan: () {},
            onRefresh: onRefresh,
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() {
    AppLogBuffer.instance.resetForTest();
    AppLogBuffer.instance.minLevel = TunnelLogLevel.debug;
    _seedDocuments();
  });

  testWidgets('a tab that lists documents offers its own refresh', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final router = await _pumpServers(tester);

    expect(find.text('Сервера'), findsOneWidget);
    expect(
      _barRefresh(),
      findsOneWidget,
      reason: 'a tab that lists saved documents has to offer a refresh',
    );
    expect(router.routeInformationProvider.value.uri.path, '/locations');
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('the key reads this tab and keeps this tab', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final router = await _pumpServers(tester);

    AppLogBuffer.instance.clear();
    await tester.tap(_barRefresh(), warnIfMissed: true);
    await tester.pump();

    final path = router.routeInformationProvider.value.uri.path;
    final lines = AppLogBuffer.instance.recentLines().join('\n');

    expect(
      lines.contains('ui.action screen=locations action=refresh'),
      isTrue,
      reason: 'the press was never logged against this tab:\n$lines',
    );
    expect(
      lines.contains('screen=home action=refresh'),
      isFalse,
      reason: 'the profile tab refreshed instead:\n$lines',
    );
    expect(path, '/locations');
    expect(find.text('ПРОФИЛЬ'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('the ring on a plate keeps this tab too', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final router = await _pumpServers(tester);

    final rings = find.byType(AppRingButton);
    expect(rings, findsWidgets);
    AppLogBuffer.instance.clear();
    await tester.tap(rings.first, warnIfMissed: true);
    await tester.pump();

    expect(
      router.routeInformationProvider.value.uri.path,
      '/locations',
      reason: 'reloading a document is not picking a server',
    );
    expect(find.text('ПРОФИЛЬ'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('the answer does not swallow the key that asked', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await _pumpServers(tester);

    // The keys sit on the bottom edge of the page and the answer rises from
    // the bottom of the same Scaffold. Without standing room the toast owns
    // that whole band: for 2.2 seconds the refresh key cannot be pressed again,
    // which reads as a dead button and sends the person looking for the answer
    // somewhere else.
    AppLogBuffer.instance.clear();
    await tester.tapAt(tester.getCenter(_barRefresh()));
    await tester.pump();

    expect(
      AppLogBuffer.instance
          .recentLines()
          .join('\n')
          .contains('ui.action screen=locations action=refresh'),
      isTrue,
      reason: 'the answer was still up and the key did not answer',
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('on a window the bar answers with a full key that works', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    var pressed = 0;
    await _pumpBar(tester, onRefresh: () => pressed++);
    await tester.pump();

    expect(find.byType(AppActionButton), findsNWidgets(2));
    final refresh = find.widgetWithText(AppActionButton, 'Обновить');
    expect(refresh, findsOneWidget);
    await tester.tap(refresh, warnIfMissed: true);
    await tester.pump();
    expect(pressed, 1, reason: 'the key was painted but had no handler');
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a window with nothing to reload does not paint a dead key', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await _pumpBar(tester);
    await tester.pump();

    // No document behind anything on the page: one key, the one that adds.
    expect(find.byType(AppActionButton), findsOneWidget);
    expect(find.widgetWithText(AppActionButton, 'Обновить'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
}
