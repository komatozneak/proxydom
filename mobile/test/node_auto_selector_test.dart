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

  test('Auto never picks hidden EU TT fallback', () async {
    const selector = NodeAutoSelector(timeout: Duration(milliseconds: 80));
    const nodes = [
      VpnNode(
        id: 'eu-primary',
        label: 'EU',
        host: '127.0.0.1',
        port: 9,
        status: 'connected',
        isDefault: true,
      ),
      VpnNode(
        id: 'eu-tt-1',
        label: 'EU',
        host: '127.0.0.1',
        port: 443,
        status: 'connected',
        isDefault: false,
        protocol: kVpnNodeProtocolTrusttunnel,
        purpose: 'general',
        region: 'eu',
        autoEligible: true,
      ),
    ];
    final id = await selector.pickBestNodeId(nodes);
    expect(id, 'eu-primary');
  });

  test('Auto may pick Free US TT when it is the only eligible node', () async {
    const selector = NodeAutoSelector(timeout: Duration(milliseconds: 80));
    const nodes = [
      VpnNode(
        id: 'us-geo-1',
        label: 'США',
        host: '127.0.0.1',
        port: 9,
        status: 'connected',
        isDefault: false,
        protocol: kVpnNodeProtocolTrusttunnel,
        purpose: 'geo-us',
        region: 'us',
        autoEligible: true,
      ),
      VpnNode(
        id: 'al-youtube',
        label: 'YouTube',
        host: '127.0.0.1',
        port: 443,
        status: 'connected',
        isDefault: false,
        protocol: kVpnNodeProtocolTrusttunnel,
        purpose: 'youtube',
        autoEligible: false,
      ),
    ];
    final id = await selector.pickBestNodeId(nodes);
    expect(id, 'us-geo-1');
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
