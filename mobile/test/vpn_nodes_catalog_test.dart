import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/core/vpn_nodes.dart';
import 'package:teremok_connect/features/vpn/data/vpn_node.dart';

void main() {
  test('SelectedRegionStore key is selected_region_id', () {
    expect(SelectedRegionStore.key, 'selected_region_id');
  });

  test('VpnNode maps connected status', () {
    const node = VpnNode(
      id: '1',
      label: 'Node 217',
      host: '217.0.0.1',
      port: 443,
      status: 'connected',
      isDefault: false,
    );
    expect(node.isConnected, isTrue);
  });
}
