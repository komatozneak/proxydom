import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/features/vpn/data/node_display.dart';
import 'package:teremok_connect/features/vpn/data/vpn_node.dart';

void main() {
  group('real server pool labels', () {
    test('known hosts resolve to country/city with flags', () {
      const cases = <String, (String, String, String)>{
        '185.139.228.192': ('Нидерланды', 'Амстердам', '🇳🇱'),
        '45.91.248.91': ('США · Бесплатно', '', '🇺🇸'),
        '217.60.3.9': ('Европа · Бесплатно', '', '🇪🇺'),
        '107.181.139.193': ('Индия · Premium', '', '🇮🇳'),
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
      expect(place.title, 'США · Бесплатно');
      expect(place.flag, '🇺🇸');
    });

    test('Hy2 place uses Europe free copy not Восточная Европа Xray', () {
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
      expect(place.title, 'Европа · Бесплатно');
      expect(place.title.toLowerCase(), isNot(contains('восточная')));
      expect(place.flag, kFlagEurope);
    });

    test('catalog Europe label beats EU IP geo and uses EU flag', () {
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
      expect(place.title, 'Европа · Бесплатно');
      expect(place.title.toLowerCase(), isNot(contains('франкфурт')));
      expect(place.title.toLowerCase(), isNot(contains('германия')));
      expect(place.flag, kFlagEurope);
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
      expect(place.title, 'США · Бесплатно');
      expect(place.flag, kFlagUsa);
      expect(place.flag, isNot(kFlagEurope));
      expect(place.flag, isNot(kFlagGlobe));
    });

    test('normalizeNodeHost strips IPv4 port', () {
      expect(normalizeNodeHost('217.60.11.56:443'), '217.60.11.56');
      expect(normalizeNodeHost(' 45.91.248.91 '), '45.91.248.91');
    });

    test('FQDN host never appears in title or subtitle', () {
      const tt = VpnNode(
        id: 'tt-us',
        label: 'tt-us.teremokconnect.online',
        host: 'tt-us.teremokconnect.online',
        port: 443,
        status: 'connected',
        isDefault: false,
        name: 'tt-us',
        protocol: 'trusttunnel',
      );
      final place = placeForNode(tt, index: 0);
      expect(place.title.toLowerCase(), isNot(contains('teremokconnect')));
      expect(place.title.toLowerCase(), isNot(contains('tt-')));
      expect(place.subtitle.toLowerCase(), isNot(contains('teremokconnect')));
      expect(place.subtitle, isNot(contains('.')));
      expect(place.title, 'Сервер 1');
      expect(place.subtitle, isEmpty);
    });

    test('gaming purpose shows Игровой · Premium with gamepad, not Germany', () {
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
      expect(place.title, 'Игровой · Premium');
      expect(place.flag, '🎮');
      expect(place.title.toLowerCase(), isNot(contains('германия')));
      expect(place.title.toLowerCase(), isNot(contains('germany')));
    });

    test('Free EU Xray host uses Europe free copy not Frankfurt', () {
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
      expect(place.title, 'Европа · Бесплатно');
      expect(place.flag, kFlagEurope);
      expect(place.title.toLowerCase(), isNot(contains('франкфурт')));
    });

    test('youtube purpose shows YouTube · Premium with crown, not Albania', () {
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
      expect(place.title, 'YouTube · Premium');
      expect(place.flag, '👑');
      expect(place.title.toLowerCase(), isNot(contains('албания')));
      expect(place.title.toLowerCase(), isNot(contains('albania')));
      expect(place.subtitle, isEmpty);
    });

    test('geo-in purpose shows Индия · Premium with India flag', () {
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
      expect(place.title, 'Индия · Premium');
      expect(place.flag, '🇮🇳');
      expect(locationSectionFor(india), LocationSection.premium);
    });

    test('groupNodesByLocationSection order Premium Europe USA', () {
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
      expect(g[LocationSection.premium]!.single.id, 'yt');
      expect(g[LocationSection.europe]!.single.id, 'eu');
      expect(g[LocationSection.usa]!.single.id, 'us');
      expect(g[LocationSection.other], isEmpty);
    });
  });
}
