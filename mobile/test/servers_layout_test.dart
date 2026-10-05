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
    (text: '2aq93K0', accent: false),
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
      keyHandle: '2aq93K0',
    );
    expect(facts.map((fact) => fact.text), ['2aq93K0', '14 ГБ']);
    expect(facts.map((fact) => fact.accent), [false, true]);
    expect(
      profileUpdatedLabel(
        lastUpdated: '2026-10-04T12:22:09Z',
        russian: true,
      ),
      'обновлено 04.10',
    );
  });

  testWidgets('the update stamp sits under the rings, not beside the traffic',
      (tester) async {
    tester.view
      ..physicalSize = const Size(520, 800) * _dpr
      ..devicePixelRatio = _dpr;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(_instrument()));
    await tester.pump();

    final handle = tester.getRect(find.text('2AQ93K0'));
    final traffic = tester.getRect(find.text('14 ГБ'));
    final updated = tester.getRect(find.text('ОБНОВЛЕНО 04.10'));
    final rings = find.byType(AppRingButton);
    var span = tester.getRect(rings.at(0));
    span = span.expandToInclude(tester.getRect(rings.at(1)));
    span = span.expandToInclude(tester.getRect(rings.at(2)));

    // The key and the traffic are one line. The stamp used to be the third
    // reading on that line, jammed against the figure it does not describe.
    expect(traffic.center.dy, closeTo(handle.center.dy, 2));
    expect(updated.top, greaterThan(span.bottom - 1));
    expect(updated.right, closeTo(span.right, 1.5));
  });

  testWidgets('the actions are three rings, not three framed squares',
      (tester) async {
    await tester.pumpWidget(_wrap(_instrument()));
    await tester.pump();

    expect(find.byType(AppRingButton), findsNWidgets(3));
    // A ring, so nothing on the card wears a frame but the card itself.
    for (final ring
        in tester.widgetList<AppRingButton>(find.byType(AppRingButton))) {
      expect(ring.size, lessThan(34));
    }
  });

  testWidgets('copy wears the add-server gold and delete wears clay',
      (tester) async {
    await tester.pumpWidget(_wrap(_instrument()));
    await tester.pump();

    final rings = tester
        .widgetList<AppRingButton>(find.byType(AppRingButton))
        .toList();
    expect(rings, hasLength(3));
    expect(rings[0].color, AppBrand.actionSky);
    expect(rings[1].color, AppBrand.mascotGold);
    expect(rings[2].color, AppBrand.actionClay);
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

    expect(find.text('YouTube'), findsOneWidget);
    expect(find.text('США'), findsOneWidget);
    // One rule between two lines, and none around them: the rows used to be
    // four cards inside the card.
    expect(find.byType(NodeRule), findsNWidgets(3));
    expect(find.text('УЗЛЫ'), findsOneWidget);
    expect(find.text('АКТИВЕН'), findsOneWidget);
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
    final nodes = tester.getRect(find.text('УЗЛЫ'));
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
    expect(find.text('ТЕРЕМОК'), findsWidgets);
    expect(find.text('УЗЛЫ'), findsOneWidget);

    // The key bar is on the same two lines as the list above it.
    final key = tester.getRect(find.text('Добавить сервер'));
    expect(key.left, greaterThanOrEqualTo(AppBrand.pageGutter));
    expect(find.byType(AppActionButton), findsWidgets);
  });
}
