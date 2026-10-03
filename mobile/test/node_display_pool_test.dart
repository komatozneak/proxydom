import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/features/vpn/data/node_auto_selector.dart';
import 'package:proxydom/features/vpn/data/node_display.dart';
import 'package:proxydom/features/vpn/data/vpn_node.dart';
import 'package:proxydom/l10n/app_localizations.dart';

void main() {
  group('real server pool labels', () {
    test('known hosts resolve to country/city with flags', () {
      const cases = <String, (String, String, String)>{
        '185.139.228.192': ('Нидерланды', 'Амстердам', '🇳🇱'),
        '45.91.248.91': ('США', '', '🇺🇸'),
        '217.60.3.9': ('Латвия', 'Низкий пинг', '🇱🇻'),
        '107.181.139.193': ('Индия', '', '🇮🇳'),
      };

      for (final entry in cases.entries) {
        final place = placeForHost(entry.key);
        expect(place.title, entry.value.$1, reason: entry.key);
        expect(place.subtitle, entry.value.$2, reason: entry.key);
        expect(place.flag, entry.value.$3, reason: entry.key);
        expect(isResolvedPlace(place), isTrue);
      }
    });

    test('EU primary IP is not hardcoded Frankfurt', () {
      final place = placeForHost('204.11.2.216');
      expect(place.title.toLowerCase(), isNot(contains('франкфурт')));
      expect(place.title.toLowerCase(), isNot(contains('германия')));
      expect(place.subtitle.toLowerCase(), isNot(contains('франкфурт')));
    });

    test('host:port still matches known pool', () {
      final place = placeForHost('185.139.228.192:62050');
      expect(place.title, 'Нидерланды');
      expect(place.flag, '🇳🇱');
    });

    test('ops labels and bare IPs never become titles', () {
      const node185 = VpnNode(
        id: 'node-185',
        label: '185.139.228.192',
        host: '185.139.228.192',
        port: 443,
        status: 'error',
        isDefault: false,
        name: 'node-185',
      );
      final place = placeForNode(node185, index: 1);
      expect(place.title, 'Нидерланды');
      expect(place.title, isNot(contains('185')));
      expect(place.title, isNot(contains('Сервер')));
    });

    test('USA node is not Сервер N', () {
      const usa = VpnNode(
        id: 'node-usa',
        label: 'Node USA',
        host: '45.91.248.91',
        port: 443,
        status: 'connected',
        isDefault: false,
        name: 'node-usa',
      );
      final place = placeForNode(usa, index: 3);
      expect(place.title, 'США');
      expect(place.flag, '🇺🇸');
    });

    test('Hy2 place uses Latvia free copy not Восточная Европа Xray', () {
      const hy2 = VpnNode(
        id: 'eu-hy2-1',
        label: 'Европа · Бесплатно',
        host: '217.60.3.9',
        port: 443,
        status: 'connected',
        isDefault: false,
        protocol: kVpnNodeProtocolHysteria2,
        region: 'eu',
      );
      final place = placeForNode(hy2, index: 0);
      expect(place.title, 'Латвия');
      expect(place.title.toLowerCase(), isNot(contains('восточная')));
      expect(place.flag, '🇱🇻');
    });

    test('catalog Europe label beats EU IP geo and uses LV flag', () {
      const eu = VpnNode(
        id: 'eu-hy2-1',
        label: 'Европа · Бесплатно',
        host: '217.60.3.9',
        port: 443,
        status: 'connected',
        isDefault: true,
        name: 'eu-hy2-1',
        region: 'eu',
        protocol: kVpnNodeProtocolHysteria2,
      );
      final place = placeForNode(eu, index: 0);
      expect(place.title, 'Латвия');
      expect(place.displayTitle('en'), 'Latvia');
      expect(place.displaySubtitle('en'), 'Low ping');
      expect(place.title, isNot(contains('Бесплатно')));
      expect(place.title.toLowerCase(), isNot(contains('франкфурт')));
      expect(place.title.toLowerCase(), isNot(contains('германия')));
      expect(place.flag, '🇱🇻');
      expect(place.flag, isNot(kFlagGlobe));
      expect(place.flag, isNot(kFlagUsa));
    });

    test('catalog USA product label uses US flag not globe', () {
      const usa = VpnNode(
        id: 'us-geo-1',
        label: 'США · Бесплатно',
        host: '45.91.248.91',
        port: 443,
        status: 'connected',
        isDefault: false,
        name: 'us-geo-1',
        region: 'us',
        purpose: 'geo-us',
      );
      final place = placeForNode(usa, index: 0);
      expect(place.title, 'США');
      expect(place.flag, kFlagUsa);
      expect(place.flag, isNot('🇱🇻'));
      expect(place.flag, isNot(kFlagGlobe));
      expect(place.displayTitle('en'), 'USA');
      expect(place.displayTitle('en'), isNot(contains('Free')));
      expect(place.displayTitle('ru'), 'США');
      expect(place.displayTitle('ru'), isNot(contains('Бесплатно')));
    });

    test('Hy2 catalog USA is USA in English without · Free', () {
      const usa = VpnNode(
        id: 'us-hy2-1',
        label: 'США · Бесплатно',
        host: '45.91.248.91',
        port: 443,
        status: 'connected',
        isDefault: false,
        protocol: kVpnNodeProtocolHysteria2,
        region: 'us',
        purpose: 'geo-us',
      );
      final place = placeForNode(usa, index: 0);
      expect(place.displayTitle('en'), 'USA');
      expect(place.displaySubtitle('en'), isNot(contains('Free')));
      expect(place.displayTitle('ru'), 'США');
      expect(place.title, isNot(contains('·')));
      expect(place.title, isNot(contains('Бесплатно')));
    });

    test('stripTierRole drops catalog Free and Premium suffixes', () {
      expect(stripTierRole('США · Бесплатно'), 'США');
      expect(stripTierRole('USA · Free'), 'USA');
      expect(stripTierRole('USA. Free'), 'USA');
      expect(stripTierRole('Латвия'), 'Латвия');
      expect(stripTierRole('YouTube · Premium'), 'YouTube');
      expect(stripTierRole('Индия · Премиум'), 'Индия');
    });

    test('displaySubtitleForNode keeps marketing blurb (no lock disclaimer)',
        () {
      final l = lookupAppL10n(const Locale('ru'));
      const yt = VpnNode(
        id: 'al-youtube',
        label: 'YouTube · Premium',
        host: '85.155.228.235',
        port: 443,
        status: 'connected',
        isDefault: false,
        purpose: 'youtube',
        requiresPremium: true,
      );
      const game = VpnNode(
        id: 'eu-gaming',
        label: 'Игровой · Premium',
        host: '204.11.2.216',
        port: 443,
        status: 'connected',
        isDefault: false,
        purpose: 'gaming',
        requiresPremium: true,
      );
      expect(displaySubtitleForNode(yt, l), l.regionBlurbYoutube);
      expect(displaySubtitleForNode(game, l), l.regionBlurbGaming);
    });

    test('normalizeNodeHost strips IPv4 port', () {
      expect(normalizeNodeHost('217.60.11.56:443'), '217.60.11.56');
      expect(normalizeNodeHost(' 45.91.248.91 '), '45.91.248.91');
    });

    test('FQDN host never appears in title or subtitle', () {
      const tt = VpnNode(
        id: 'tt-us',
        label: 'node.proxydom.su',
        host: 'node.proxydom.su',
        port: 443,
        status: 'connected',
        isDefault: false,
        name: 'tt-us',
        protocol: 'trusttunnel',
      );
      final place = placeForNode(tt, index: 0);
      expect(place.title.toLowerCase(), isNot(contains('proxydom')));
      expect(place.title.toLowerCase(), isNot(contains('tt-')));
      expect(place.subtitle.toLowerCase(), isNot(contains('proxydom')));
      expect(place.subtitle, isNot(contains('.')));
      expect(place.title, 'Сервер 1');
      expect(place.subtitle, isEmpty);
    });

    test('gaming purpose shows Игровой with gamepad, not Germany', () {
      const game = VpnNode(
        id: 'eu-gaming',
        label: 'Германия',
        host: '204.11.2.216',
        port: 443,
        status: 'connected',
        isDefault: false,
        name: 'eu-gaming',
        protocol: 'trusttunnel',
        purpose: 'gaming',
        region: 'eu',
        requiresPremium: true,
      );
      final place = placeForNode(game, index: 1);
      expect(place.title, 'Игровой');
      expect(place.flag, 'gaming');
      expect(place.title.toLowerCase(), isNot(contains('германия')));
      expect(place.title.toLowerCase(), isNot(contains('germany')));
    });

    test('Free EU Xray host uses Latvia free copy not Frankfurt', () {
      const eu = VpnNode(
        id: 'eu-geo-1',
        label: 'Node EU',
        host: '217.60.3.9',
        port: 443,
        status: 'connected',
        isDefault: false,
        name: 'eu-geo-1',
        region: 'eu',
      );
      final place = placeForNode(eu, index: 0);
      expect(place.title, 'Латвия');
      expect(place.subtitle, 'Низкий пинг');
      expect(place.subtitleEn, 'Low ping');
      expect(place.flag, '🇱🇻');
      expect(place.title.toLowerCase(), isNot(contains('франкфурт')));
    });

    test('youtube purpose shows YouTube with crown, not Albania', () {
      const yt = VpnNode(
        id: 'al-youtube-tt',
        label: 'Албания · YouTube',
        host: '85.155.228.235',
        port: 443,
        status: 'connected',
        isDefault: false,
        name: 'al-youtube-tt',
        protocol: 'trusttunnel',
        purpose: 'youtube',
        region: 'al',
        requiresPremium: true,
      );
      final place = placeForNode(yt, index: 2);
      expect(place.title, 'YouTube');
      expect(place.flag, 'youtube');
      expect(place.title.toLowerCase(), isNot(contains('албания')));
      expect(place.title.toLowerCase(), isNot(contains('albania')));
      expect(place.subtitle, isEmpty);
    });

    test('geo-in purpose shows Индия with India flag', () {
      const india = VpnNode(
        id: 'in-geo-1',
        label: 'Node IN',
        host: '107.181.139.193',
        port: 443,
        status: 'connected',
        isDefault: false,
        name: 'in-geo-1',
        purpose: 'geo-in',
        region: 'in',
        protocol: kVpnNodeProtocolHysteria2,
        requiresPremium: true,
      );
      final place = placeForNode(india, index: 0);
      expect(place.title, 'Индия');
      expect(place.flag, '🇮🇳');
      expect(locationSectionFor(india), LocationSection.other);
    });

    test('groupNodesByLocationSection is a flat list without a paid section', () {
      const yt = VpnNode(
        id: 'yt',
        label: 'YouTube · Premium',
        host: '1.1.1.1',
        port: 443,
        status: 'connected',
        isDefault: false,
        purpose: 'youtube',
        requiresPremium: true,
      );
      const eu = VpnNode(
        id: 'eu',
        label: 'Европа · Бесплатно',
        host: '2.2.2.2',
        port: 443,
        status: 'connected',
        isDefault: true,
        region: 'eu',
        protocol: kVpnNodeProtocolHysteria2,
      );
      const us = VpnNode(
        id: 'us',
        label: 'США · Бесплатно',
        host: '3.3.3.3',
        port: 443,
        status: 'connected',
        isDefault: false,
        region: 'us',
      );
      final g = groupNodesByLocationSection([us, eu, yt]);
      expect(g[LocationSection.premium], isEmpty);
      expect(g[LocationSection.general]!.map((n) => n.id), ['eu', 'us']);
      expect(g[LocationSection.other]!.single.id, 'yt');
    });
  });

  test('uniqueAutoPoolFlags keeps Auto order and skips globe', () {
    const eu = VpnNode(
      id: 'eu-hy2-1',
      label: 'Европа · Бесплатно',
      host: '217.60.3.9',
      port: 443,
      status: 'connected',
      isDefault: false,
      protocol: kVpnNodeProtocolHysteria2,
      region: 'eu',
    );
    const us = VpnNode(
      id: 'us-hy2-1',
      label: 'США · Бесплатно',
      host: '45.91.248.91',
      port: 443,
      status: 'connected',
      isDefault: false,
      protocol: kVpnNodeProtocolHysteria2,
      purpose: 'geo-us',
    );
    const eu2 = VpnNode(
      id: 'eu-hy2-2',
      label: 'Европа · Бесплатно',
      host: '217.60.3.10',
      port: 443,
      status: 'connected',
      isDefault: false,
      protocol: kVpnNodeProtocolHysteria2,
      region: 'eu',
    );
    expect(uniqueAutoPoolFlags([eu, us, eu2]), [kFlagEurope, kFlagUsa]);
    expect(uniqueAutoPoolFlags(const []), [kFlagGlobe]);
  });

  test('flagForProductLabel maps Latvia copy to EU flag', () {
    expect(flagForProductLabel('Латвия'), kFlagEurope);
    expect(flagForProductLabel('Latvia'), kFlagEurope);
    expect(flagForProductLabel('латвия · бесплатно'), kFlagEurope);
  });

  test('uniqueAutoPoolFlags Free is LV→US, Premium adds gaming then YouTube',
      () {
    const eu = VpnNode(
      id: 'eu-hy2-1',
      label: 'Европа · Бесплатно',
      host: '217.60.3.9',
      port: 443,
      status: 'connected',
      isDefault: false,
      protocol: kVpnNodeProtocolHysteria2,
      region: 'eu',
    );
    const us = VpnNode(
      id: 'us-hy2-1',
      label: 'США · Бесплатно',
      host: '45.91.248.91',
      port: 443,
      status: 'connected',
      isDefault: false,
      protocol: kVpnNodeProtocolHysteria2,
      purpose: 'geo-us',
    );
    const game = VpnNode(
      id: 'eu-gaming',
      label: 'Игровой · Premium',
      host: '204.11.2.216',
      port: 443,
      status: 'connected',
      isDefault: false,
      purpose: 'gaming',
      requiresPremium: true,
    );
    const yt = VpnNode(
      id: 'al-youtube',
      label: 'YouTube · Premium',
      host: '85.155.228.235',
      port: 443,
      status: 'connected',
      isDefault: false,
      purpose: 'youtube',
      requiresPremium: true,
    );
    const india = VpnNode(
      id: 'in-geo-1',
      label: 'Индия · Премиум',
      host: '107.181.139.193',
      port: 443,
      status: 'connected',
      isDefault: false,
      purpose: 'geo-in',
      requiresPremium: true,
    );
    final catalog = [eu, us, game, yt, india];
    expect(
      uniqueAutoPoolFlags(autoPoolFor(catalog, isPremium: false)),
      [kFlagEurope, kFlagUsa],
    );
    expect(
      uniqueAutoPoolFlags(autoPoolFor(catalog, isPremium: true)),
      [kFlagEurope, kFlagUsa, kFlagGaming, 'youtube'],
    );
  });

  test('autoSelectionDisplayFlag uses winner place, else Auto-pool fallback',
      () {
    const eu = VpnNode(
      id: 'eu-hy2-1',
      label: 'Европа · Бесплатно',
      host: '217.60.3.9',
      port: 443,
      status: 'connected',
      isDefault: true,
      protocol: kVpnNodeProtocolHysteria2,
      region: 'eu',
    );
    const us = VpnNode(
      id: 'us-hy2-1',
      label: 'США · Бесплатно',
      host: '45.91.248.91',
      port: 443,
      status: 'connected',
      isDefault: false,
      protocol: kVpnNodeProtocolHysteria2,
      purpose: 'geo-us',
    );
    const yt = VpnNode(
      id: 'al-youtube',
      label: 'YouTube · Premium',
      host: '85.155.228.235',
      port: 443,
      status: 'connected',
      isDefault: false,
      purpose: 'youtube',
      requiresPremium: true,
    );
    const india = VpnNode(
      id: 'in-geo-1',
      label: 'Индия · Премиум',
      host: '107.181.139.193',
      port: 443,
      status: 'connected',
      isDefault: false,
      purpose: 'geo-in',
      requiresPremium: true,
    );
    const game = VpnNode(
      id: 'eu-gaming',
      label: 'Игровой · Premium',
      host: '204.11.2.216',
      port: 443,
      status: 'connected',
      isDefault: false,
      purpose: 'gaming',
      requiresPremium: true,
    );
    final catalog = [eu, us, yt, india, game];
    final freeFlags = uniqueAutoPoolFlags([eu, us]);
    expect(
      autoSelectionDisplayFlag(
        catalog: catalog,
        winnerId: null,
        poolFlags: freeFlags,
      ),
      kFlagEurope,
    );
    expect(
      autoSelectionDisplayFlag(
        catalog: catalog,
        winnerId: 'al-youtube',
        poolFlags: freeFlags,
      ),
      'youtube',
    );
    expect(
      autoSelectionDisplayFlag(
        catalog: catalog,
        winnerId: 'eu-gaming',
        poolFlags: freeFlags,
      ),
      'gaming',
    );
    expect(
      autoSelectionDisplayFlag(
        catalog: catalog,
        winnerId: 'in-geo-1',
        poolFlags: freeFlags,
      ),
      kFlagIndia,
    );
    expect(
      autoSelectionDisplayFlag(
        catalog: catalog,
        winnerId: 'us-hy2-1',
        poolFlags: freeFlags,
      ),
      kFlagUsa,
    );
    expect(autoWinnerNode(catalog, 'al-youtube')?.id, 'al-youtube');
    expect(autoWinnerNode(catalog, null), isNull);
    expect(
      autoSelectionDisplayFlag(
        catalog: const [],
        winnerId: null,
      ),
      kFlagGlobe,
    );
  });
}
