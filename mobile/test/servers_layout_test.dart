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
import 'package:proxydom/features/vpn/data/subscription_label.dart';
import 'package:proxydom/features/vpn/presentation/locations_screen.dart';
import 'package:proxydom/features/vpn/presentation/server_instrument.dart';
import 'package:proxydom/features/vpn/presentation/server_instrument_parts.dart';
import 'package:proxydom/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _dpr = 3.0;
const _phone = Size(360, 780);

/// One saved profile, as the store keeps it.
const _teremokLink =
    'hysteria2://pw@eu1.proxydom.su:443?sni=eu1.proxydom.su&insecure=1#%D0%A2%D0%B5%D1%80%D0%B5%D0%BC%D0%BE%D0%BA';

String _line(String name) =>
    'hysteria2://pw@eu1.proxydom.su:443?sni=eu1.proxydom.su&insecure=1#$name';

void _seedTeremok() {
  SharedPreferences.setMockInitialValues({
    'hy2_import_v1': jsonEncode({
      'catalogs': [
        {
          'id': 'teremok',
          'title': 'Теремок',
          'url': 'https://panel.proxydom.su/teremok',
          'trafficMeta': 'upload=1; download=2; total=15000000000',
          'lastUpdated': '2026-10-04T12:22:09Z',
          'announce': 'Значок справа ведёт в бота',
          'supportUrl': 'https://t.me/proxydom_bot',
          'lines': [
            _teremokLink,
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
}) {
  return ProfileInstrument(
    title: 'Теремок',
    description: 'Значок справа ведёт в бота',
    facts: facts,
    updated: updated,
    selected: false,
    onNodeTap: (_) {},
    selectedNodeTitle: 'YouTube',
    telegramLabel: 'Telegram',
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
      tile: title.contains('YouTube') ? PoolTile.youtube : PoolTile.flag,
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

  testWidgets('the key prefix is gone and the stamp sits under the actions',
      (tester) async {
    tester.view
      ..physicalSize = const Size(520, 800) * _dpr
      ..devicePixelRatio = _dpr;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(_instrument()));
    await tester.pump();

    expect(find.text('2AQ93K0'), findsNothing);
    final updated = tester.getRect(find.text('обновлено 04.10'));
    final ring = tester.getRect(find.byType(AppRingButton));
    expect(updated.top, greaterThanOrEqualTo(ring.bottom - 1));
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
    _seedTeremok();

    await tester.pumpWidget(_wrap(const LocationsScreen()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));

    final note = find.text('Значок справа ведёт в бота');
    expect(note, findsOneWidget);
    expect(tester.getSize(note).height, greaterThan(8));

    // Between the traffic reading and the pool, not dropped off the plate.
    final traffic = tester.getRect(find.textContaining('ГБ'));
    final nodes = tester.getRect(find.text('Узлы'));
    final body = tester.getRect(note);
    expect(body.top, greaterThan(traffic.bottom));
    expect(body.bottom, lessThan(nodes.top));
  });

  testWidgets('the page starts on the gutter its heading is on',
      (tester) async {
    tester.view
      ..physicalSize = _phone * _dpr
      ..devicePixelRatio = _dpr;
    addTearDown(tester.view.reset);
    _seedTeremok();

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
    expect(find.text('Теремок'), findsWidgets);
    expect(find.text('Узлы'), findsOneWidget);

    // The key bar is on the same two lines as the list above it.
    final key = tester.getRect(find.text('Добавить сервер'));
    expect(key.left, greaterThanOrEqualTo(AppBrand.pageGutter));
    expect(find.byType(AppActionButton), findsWidgets);
  });
}



