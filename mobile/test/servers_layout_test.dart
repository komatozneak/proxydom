// The Servers tab reads as one page again.
//
// It was rebuilt around its own numbers: the heading sat on the shared page
// gutter, the list on 44/16, and the key bar under it on a third pair. Every
// card therefore began 20px to the right of the word that names it. On top of
// that, every object on the tab was a box — a pill count in the heading, three
// framed squares on each card, four bordered rows inside it.
//
// These are the measurements, not the taste: the page's own left edge, one
// gutter for both halves of the page, the rules between the pool lines, and the
// three rings where the squares used to be.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/core/theme.dart';
import 'package:proxydom/core/widgets/app_action_button.dart';
import 'package:proxydom/core/widgets/app_surface.dart';
import 'package:proxydom/features/vpn/data/profile_manifest.dart';
import 'package:proxydom/features/vpn/data/subscription_label.dart';
import 'package:proxydom/features/vpn/data/subscription_traffic.dart';
import 'package:proxydom/features/vpn/presentation/locations_screen.dart';
import 'package:proxydom/features/vpn/presentation/server_instrument.dart';
import 'package:proxydom/features/vpn/presentation/server_instrument_parts.dart';
import 'package:proxydom/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _dpr = 3.0;
const _phone = Size(360, 780);

/// One saved profile, as the store keeps it.
const _profileLink =
    'hysteria2://pw@eu1.proxydom.su:443?sni=eu1.proxydom.su&insecure=1#%D0%9C%D0%BE%D0%B9%20%D0%BF%D1%80%D0%BE%D1%84%D0%B8%D0%BB%D1%8C';

String _line(String name) =>
    'hysteria2://pw@eu1.proxydom.su:443?sni=eu1.proxydom.su&insecure=1#$name';

void _seedProfile() {
  SharedPreferences.setMockInitialValues({
    'hy2_import_v1': jsonEncode({
      'catalogs': [
        {
          'id': 'profile',
          'title': 'Мой профиль',
          'url': 'https://panel.example.test/profile',
          'trafficMeta':
              'upload=5000000000; download=2500000000; total=20000000000',
          'lastUpdated': '2026-10-04T12:22:09Z',
          'announce': 'Поддержка и обновления',
          'supportUrl': 'https://t.me/example',
          'lines': [
            _profileLink,
            _line('Индия'),
            _line('Игровой'),
            _line('YouTube'),
          ],
        },
      ],
      'selected': 0,
    }),
  });
}

void _seedManyNodes(int count) {
  SharedPreferences.setMockInitialValues({
    'hy2_import_v1': jsonEncode({
      'catalogs': [
        {
          'id': 'big',
          'title': 'Большой',
          'url': 'https://panel.proxydom.su/big',
          'lines': [
            for (var i = 0; i < count; i++) _line('Узел $i'),
          ],
        },
      ],
      'selected': 0,
    }),
  });
}

Widget _wrap(Widget child, {ThemeData? theme}) {
  return ProviderScope(
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme ?? AppTheme.light,
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('ru'),
      home: child,
    ),
  );
}

ProfileInstrument _instrument({
  List<NodeLine> nodes = const [],
  List<({String text, bool accent})> facts = const [
    (text: '14 ГБ', accent: true),
  ],
  String? updated = 'обновлено 04.10',
  SubscriptionTraffic? parsedTraffic,
  ProfileTraffic? manifestTraffic,
  DateTime? trafficUpdatedAt,
  int? updateIntervalHours,
  DateTime? expiresAt,
  String? sourceLabel,
}) {
  return ProfileInstrument(
    title: 'Мой профиль',
    description: 'Поддержка и обновления',
    facts: facts,
    parsedTraffic: parsedTraffic,
    manifestTraffic: manifestTraffic,
    sourceLabel: sourceLabel,
    trafficUpdatedAt: trafficUpdatedAt,
    updateIntervalHours: updateIntervalHours,
    expiresAt: expiresAt,
    updated: updated,
    selected: false,
    onNodeTap: (_) {},
    selectedNodeTitle: 'YouTube',
    telegramLabel: 'Поддержка',
    onTelegram: () {},
    onRefresh: () {},
    onShare: () {},
    onDelete: () {},
    nodes: nodes,
  );
}

NodeLine _node(String title, {bool selected = false}) {
  return NodeLine(
    label: PoolServerLabel(
      title: title,
      subtitle: 'низкий пинг',
      tile: title.contains('YouTube') ? PoolTile.media : PoolTile.flag,
      flag: '',
    ),
    endpoint: 'eu1.proxydom.su:443',
    selected: selected,
    onTap: () {},
  );
}

void main() {
  test('only the traffic reading wears colour', () {
    final facts = profileFacts(
      trafficMeta: 'upload=1; download=2; total=15000000000',
      russian: true,
      keyHandle: '',
    );
    expect(facts.map((fact) => fact.text), ['14 ГБ']);
    expect(facts.map((fact) => fact.accent), [true]);
    expect(
      profileUpdatedLabel(
        lastUpdated: '2026-10-04T12:22:09Z',
        russian: true,
      ),
      'обновлено 04.10',
    );
  });

  testWidgets('the stamp sits beside the actions', (tester) async {
    tester.view
      ..physicalSize = const Size(520, 800) * _dpr
      ..devicePixelRatio = _dpr;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(_instrument()));
    await tester.pump();

    expect(find.text('2AQ93K0'), findsNothing);
    final updated = tester.getRect(find.text('обновлено 04.10'));
    final ring = tester.getRect(find.byType(AppRingButton));
    expect(updated.left, lessThan(ring.left));
    expect(updated.top, greaterThanOrEqualTo(ring.top - 1));
    expect(updated.bottom, lessThanOrEqualTo(ring.bottom + 1));
  });

  testWidgets('the actions sit on the right edge of the profile',
      (tester) async {
    tester.view
      ..physicalSize = const Size(520, 800) * _dpr
      ..devicePixelRatio = _dpr;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(_instrument()));
    await tester.pump();

    final card = tester.getRect(find.byType(ProfileInstrument));
    final menu = tester.getRect(find.byType(PopupMenuButton<String>));
    expect(card.right - menu.right, lessThan(20));
  });

  testWidgets('one refresh ring and one overflow, not three peer rings',
      (tester) async {
    await tester.pumpWidget(_wrap(_instrument()));
    await tester.pump();

    expect(find.byType(AppRingButton), findsOneWidget);
    expect(find.byType(PopupMenuButton<String>), findsOneWidget);
    final ring = tester.widget<AppRingButton>(find.byType(AppRingButton));
    expect(ring.size, 40);
  });

  testWidgets('the refresh ring is neutral; delete lives in the menu',
      (tester) async {
    await tester.pumpWidget(_wrap(_instrument()));
    await tester.pump();

    final ring = tester.widget<AppRingButton>(find.byType(AppRingButton));
    expect(ring.color, AppTheme.light.colorScheme.onSurfaceVariant);
    // The destructive action is still reachable, but only after opening the
    // overflow — it is not a coloured peer of refresh.
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('Удалить'), findsOneWidget);
  });

  testWidgets('the pool is ruled lines on one plate', (tester) async {
    tester.view
      ..physicalSize = _phone * _dpr
      ..devicePixelRatio = _dpr;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _wrap(
        _instrument(
          nodes: [
            _node('YouTube', selected: true),
            _node('Индия'),
            _node('Игровой'),
            _node('США'),
          ],
        ),
      ),
    );
    await tester.pump();

    // The active line is named in the header and again in the pool.
    expect(find.text('YouTube'), findsWidgets);
    expect(find.text('США'), findsOneWidget);
    // One rule between two lines, and none around them: the rows used to be
    // four cards inside the card.
    expect(find.byType(NodeRule), findsNWidgets(3));
    expect(find.text('Узлы'), findsOneWidget);
    expect(find.text('Активен'), findsOneWidget);
  });

  testWidgets('a saved announcement is on the profile card', (tester) async {
    tester.view
      ..physicalSize = _phone * _dpr
      ..devicePixelRatio = _dpr;
    addTearDown(tester.view.reset);
    _seedProfile();

    await tester.pumpWidget(_wrap(const LocationsScreen()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));

    final note = find.text('Поддержка и обновления');
    expect(note, findsOneWidget);
    expect(tester.getSize(note).height, greaterThan(8));

    // Between the traffic bar and the pool, not dropped off the plate.
    final traffic = tester.getRect(find.byKey(kProfileTrafficBarKey));
    final nodes = tester.getRect(find.text('Узлы'));
    final body = tester.getRect(note);
    expect(body.top, greaterThan(traffic.bottom));
    expect(body.bottom, lessThan(nodes.top));
  });

  testWidgets('a capped profile gets its own traffic bar', (tester) async {
    await tester.pumpWidget(
      _wrap(
        _instrument(
          parsedTraffic: const SubscriptionTraffic(
            upload: 5 * 1024 * 1024 * 1024,
            download: 5 * 1024 * 1024 * 1024,
            total: 20 * 1024 * 1024 * 1024,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(kProfileTrafficBarKey), findsOneWidget);
    expect(find.text('использовано 10 ГБ / 20 ГБ'), findsOneWidget);
    expect(find.text('ОСТАЛОСЬ'), findsOneWidget);
    expect(find.text('50%'), findsNothing);
  });

  testWidgets('the rail shows what is left, not what was spent',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        _instrument(
          parsedTraffic: const SubscriptionTraffic(
            upload: 0,
            download: 15 * 1024 * 1024 * 1024,
            total: 20 * 1024 * 1024 * 1024,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final fill = tester.widget<FractionallySizedBox>(
      find.byKey(kProfileTrafficFillKey),
    );
    expect(fill.widthFactor, closeTo(0.25, 0.001));
    expect(find.text('использовано 15 ГБ / 20 ГБ'), findsOneWidget);
  });

  testWidgets('unlimited, unknown and used-only states are distinct',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        _instrument(
          facts: const [],
          manifestTraffic: const ProfileTraffic(
            unlimited: true,
            download: 123456789,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('БЕЗ ЛИМИТА'), findsOneWidget);
    expect(find.byKey(kProfileTrafficBarKey), findsNothing);

    await tester.pumpWidget(
      _wrap(_instrument(facts: const [])),
    );
    await tester.pump();
    expect(find.text('нет данных о лимите'), findsOneWidget);
    expect(find.byKey(kProfileTrafficBarKey), findsNothing);

    await tester.pumpWidget(
      _wrap(
        _instrument(
          facts: const [],
          manifestTraffic: const ProfileTraffic(download: 27000000000),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('нет данных о лимите'), findsOneWidget);
    expect(find.byKey(kProfileTrafficBarKey), findsNothing);
  });

  testWidgets('a 1 TB profile shows an honest decimal total', (tester) async {
    await tester.pumpWidget(
      _wrap(
        _instrument(
          facts: const [],
          manifestTraffic: const ProfileTraffic(
            download: 27000000000,
            total: 1000000000000,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('973 ГБ'), findsOneWidget);
    expect(find.text('ОСТАЛОСЬ'), findsOneWidget);
    expect(find.text('использовано 27 ГБ / 1 ТБ'), findsOneWidget);
    expect(find.text('2,7%'), findsNothing);
  });

  testWidgets('exhausted and stale profiles keep their facts', (tester) async {
    await tester.pumpWidget(
      _wrap(
        _instrument(
          facts: const [],
          manifestTraffic: const ProfileTraffic(
            download: 100000000000,
            total: 100000000000,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Трафик закончился'), findsOneWidget);
    expect(find.text('100%'), findsNothing);

    await tester.pumpWidget(
      _wrap(
        _instrument(
          facts: const [],
          updated: 'обновлено 01.10',
          trafficUpdatedAt: DateTime.utc(2026, 10, 1),
          manifestTraffic: const ProfileTraffic(
            download: 27000000000,
            total: 100000000000,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('устарело'), findsOneWidget);
    expect(find.text('73 ГБ'), findsOneWidget);
  });

  testWidgets('a capped profile shows its expiry date', (tester) async {
    await tester.pumpWidget(
      _wrap(
        _instrument(
          facts: const [],
          expiresAt: DateTime.utc(2027, 9, 29),
          manifestTraffic: const ProfileTraffic(
            download: 2000000000,
            total: 10000000000,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('истекает: 29.09.2027'), findsOneWidget);
  });

  testWidgets('the card names the document it was loaded from', (tester) async {
    await tester.pumpWidget(
      _wrap(
        _instrument(
          facts: const [],
          sourceLabel: 'id.docdn.pro',
        ),
      ),
    );
    await tester.pump();

    expect(find.text('id.docdn.pro'), findsOneWidget);
  });

  testWidgets('profile and nodes are two sections of one plate',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        SingleChildScrollView(
          child: _instrument(nodes: [_node('Москва')]),
        ),
      ),
    );
    await tester.pump();

    final card = find.byType(ProfileInstrument);
    expect(
      find.descendant(of: card, matching: find.byType(AppSurface)),
      findsOneWidget,
    );
  });

  testWidgets('the page starts on the gutter its heading is on',
      (tester) async {
    tester.view
      ..physicalSize = _phone * _dpr
      ..devicePixelRatio = _dpr;
    addTearDown(tester.view.reset);
    _seedProfile();

    await tester.pumpWidget(_wrap(const LocationsScreen()));
    await tester.pump();
    // The tab reads its document and polls the native side on boot; four
    // seconds of fake time is what the gutter test gives it too.
    await tester.pump(const Duration(seconds: 4));

    expect(find.text('Сервера'), findsOneWidget);
    final heading = tester.getRect(find.text('Сервера'));
    // The plate, not the words inside it: the name is inset by the card's own
    // padding, and the card is what has to sit on the page's left line.
    final card = tester.getRect(find.byType(ProfileInstrument));
    expect(heading.left, AppBrand.pageGutter);
    expect(card.left, AppBrand.pageGutter);
    expect(find.text('Мой профиль'), findsWidgets);
    expect(find.text('Узлы'), findsOneWidget);

    // The key bar is on the same two lines as the list above it.
    final key = tester.getRect(find.text('Добавить сервер'));
    expect(key.left, greaterThanOrEqualTo(AppBrand.pageGutter));
    expect(find.byType(AppActionButton), findsWidgets);
  });

  testWidgets('a profile over eight nodes offers search and filters lines',
      (tester) async {
    tester.view
      ..physicalSize = _phone * _dpr
      ..devicePixelRatio = _dpr;
    addTearDown(tester.view.reset);
    _seedManyNodes(10);

    await tester.pumpWidget(_wrap(const LocationsScreen()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Узел 8'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Узел 9');
    await tester.pump();
    // The field itself also contains the query text.
    expect(find.text('Узел 9'), findsWidgets);
    expect(find.text('Узел 8'), findsNothing);

    await tester.enterText(find.byType(TextField), 'нет такого');
    await tester.pump();
    expect(find.text('Серверы не найдены'), findsOneWidget);
  });

  testWidgets('a short profile has no search line', (tester) async {
    _seedProfile();
    await tester.pumpWidget(_wrap(const LocationsScreen()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));

    expect(find.byType(TextField), findsNothing);
  });
}
