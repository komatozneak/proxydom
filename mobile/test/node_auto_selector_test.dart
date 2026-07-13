import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/features/vpn/data/node_auto_selector.dart';
import 'package:teremok_connect/features/vpn/data/vpn_node.dart';

void main() {
  test('pickBestNodeId returns sole online node', () async {
    const selector = NodeAutoSelector(timeout: Duration(milliseconds: 100));
    const nodes = [
      VpnNode(
        id: 'node-185',
        label: 'NL',
        host: '185.139.228.192',
        port: 443,
        status: 'connected',
        isDefault: false,
      ),
    ];
    final id = await selector.pickBestNodeId(nodes);
    expect(id, 'node-185');
  });

  test('resolveNodeIdForConfig returns stored id when not auto', () async {
    const nodes = [
      VpnNode(
        id: 'node-usa',
        label: 'USA',
        host: '45.91.248.91',
        port: 443,
        status: 'connected',
        isDefault: false,
      ),
    ];
    final id = await resolveNodeIdForConfig(
      storedId: 'node-usa',
      catalog: nodes,
      selector: const NodeAutoSelector(timeout: Duration(milliseconds: 50)),
    );
    expect(id, 'node-usa');
  });
}
