import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/features/vpn/data/vpn_node.dart';
import 'package:teremok_connect/features/vpn/data/vpn_nodes_repository.dart';

/// Catalog resolution used by [VpnNotifier.fetchConfig] for concrete node ids.
List<VpnNode>? preferCachedCatalog({
  required List<VpnNode>? cached,
  required String nodeId,
  required List<VpnNode> Function() live,
}) {
  final cachedHasNode =
      cached != null && cached.any((n) => n.id == nodeId);
  if (cachedHasNode) return cached;
  return live();
}

void main() {
  const eu = VpnNode(
    id: 'eu-primary',
    host: '31.59.103.144',
    port: 443,
    label: 'Europe',
    status: 'up',
    isDefault: true,
    protocol: 'vless-reality',
  );
  const us = VpnNode(
    id: 'us-youtube-tt',
    host: '45.91.248.91',
    port: 443,
    label: 'USA',
    status: 'up',
    isDefault: false,
    protocol: 'trusttunnel',
  );

  test('preferCachedCatalog skips live listNodes when node is cached', () {
    var liveCalls = 0;
    final result = preferCachedCatalog(
      cached: const [eu, us],
      nodeId: 'eu-primary',
      live: () {
        liveCalls++;
        return const [eu];
      },
    );
    expect(result, const [eu, us]);
    expect(liveCalls, 0);
  });

  test('preferCachedCatalog fetches live when cache misses node', () {
    var liveCalls = 0;
    final result = preferCachedCatalog(
      cached: const [us],
      nodeId: 'eu-primary',
      live: () {
        liveCalls++;
        return const [eu, us];
      },
    );
    expect(result?.map((n) => n.id), ['eu-primary', 'us-youtube-tt']);
    expect(liveCalls, 1);
  });

  test('preferCachedCatalog fetches live when cache empty', () {
    var liveCalls = 0;
    preferCachedCatalog(
      cached: null,
      nodeId: 'eu-primary',
      live: () {
        liveCalls++;
        return const [eu];
      },
    );
    expect(liveCalls, 1);
  });

  test('VpnNodesRepository exposes loadCachedNodes for switch path', () {
    // Compile-time contract: switch path must be able to read disk cache.
    expect(VpnNodesRepository().loadCachedNodes, isA<Function>());
  });
}
