import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/features/vpn/data/vpn_node.dart';

void main() {
  test('VpnNode.fromJson parses Marzban catalog entry', () {
    final node = VpnNode.fromJson({
      'id': 'node-185',
      'label': 'EU West',
      'host': '185.139.228.192',
      'port': 443,
      'status': 'connected',
      'is_default': false,
      'name': 'node-185',
    });
    expect(node.id, 'node-185');
    expect(node.host, '185.139.228.192');
    expect(node.isConnected, isTrue);
    expect(node.isDefault, isFalse);
  });
}
