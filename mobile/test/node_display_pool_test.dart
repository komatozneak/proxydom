import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/features/vpn/data/node_display.dart';
import 'package:teremok_connect/features/vpn/data/vpn_node.dart';

void main() {
  group('real server pool labels', () {
    test('known hosts resolve to country/city with flags', () {
      const cases = <String, (String, String, String)>{
        '204.11.2.216': ('Германия', 'Франкфурт', '🇩🇪'),
        '185.139.228.192': ('Нидерланды', 'Амстердам', '🇳🇱'),
        '217.60.11.56': ('Германия', 'Франкфурт', '🇩🇪'),
        '45.91.248.91': ('США', 'Нью-Йорк', '🇺🇸'),
      };

      for (final entry in cases.entries) {
        final place = placeForHost(entry.key);
        expect(place.title, entry.value.$1, reason: entry.key);
        expect(place.subtitle, entry.value.$2, reason: entry.key);
        expect(place.flag, entry.value.$3, reason: entry.key);
        expect(isResolvedPlace(place), isTrue);
      }
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
      expect(place.subtitle, 'Нью-Йорк');
      expect(place.flag, '🇺🇸');
    });

    test('normalizeNodeHost strips IPv4 port', () {
      expect(normalizeNodeHost('217.60.11.56:443'), '217.60.11.56');
      expect(normalizeNodeHost(' 45.91.248.91 '), '45.91.248.91');
    });
  });
}
