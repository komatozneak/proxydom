import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/core/theme.dart';
import 'package:proxydom/core/widgets/app_icon.dart';
import 'package:proxydom/features/vpn/presentation/locations_screen.dart';
import 'package:proxydom/features/vpn/presentation/server_instrument.dart';
import 'package:proxydom/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _dpr = 3.0;
const _phone = Size(360, 780);

String _line(String name) =>
    'hysteria2://pw@eu1.example.test:443?sni=eu1.example.test&insecure=1#$name';

Widget _wrap(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('ru'),
      home: child,
    ),
  );
}

void _seedProfile({String? webPageUrl}) {
  SharedPreferences.setMockInitialValues({
    'hy2_import_v1': jsonEncode({
      'catalogs': [
        {
          'id': 'profile',
          'title': 'Мой профиль',
          'url': 'https://panel.example.test/profile',
          'announce': 'Продление на сайте',
          'supportUrl': 'https://t.me/example',
          if (webPageUrl != null) 'webPageUrl': webPageUrl,
          'lines': [_line('Медиа')],
        },
      ],
      'selected': 0,
    }),
  });
}

void main() {
  testWidgets('the provider page opens from its own action', (tester) async {
    var opened = 0;
    await tester.pumpWidget(
      _wrap(
        ProfileInstrument(
          title: 'Мой профиль',
          description: 'Продление на сайте',
          facts: const [],
          selected: false,
          nodes: const [],
          onNodeTap: (_) {},
          telegramLabel: 'Telegram',
          telegramIcon: AppIcons.paperPlane,
          onTelegram: () {},
          siteLabel: 'Поддержка',
          onSite: () => opened++,
        ),
      ),
    );

    expect(find.text('Telegram'), findsOneWidget);
    expect(find.byIcon(AppIcons.paperPlane), findsOneWidget);

    await tester.tap(find.text('Поддержка'));
    await tester.pump();

    expect(opened, 1);
  });

  testWidgets('a document page is a second action on the profile card',
      (tester) async {
    tester.view
      ..physicalSize = _phone * _dpr
      ..devicePixelRatio = _dpr;
    addTearDown(tester.view.reset);
    _seedProfile(webPageUrl: 'https://keydoma.site/r/abc');

    await tester.pumpWidget(_wrap(const LocationsScreen()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));

    expect(find.text('Telegram'), findsOneWidget);
    expect(find.text('Поддержка'), findsOneWidget);
  });

  testWidgets('a plain-http page is not offered', (tester) async {
    tester.view
      ..physicalSize = _phone * _dpr
      ..devicePixelRatio = _dpr;
    addTearDown(tester.view.reset);
    _seedProfile(webPageUrl: 'http://keydoma.site/r/abc');

    await tester.pumpWidget(_wrap(const LocationsScreen()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));

    expect(find.text('Telegram'), findsOneWidget);
    expect(find.text('Поддержка'), findsNothing);
  });
}
