import 'dart:async';
import 'dart:io';

import 'node_display.dart';
import 'vpn_node.dart';

/// Picks the lowest-latency online egress for «Авто» (TCP :443 probe).
class NodeAutoSelector {
  const NodeAutoSelector({
    this.probePort = 443,
    this.timeout = const Duration(seconds: 2),
  });

  final int probePort;
  final Duration timeout;

  /// Returns best [VpnNode.id], or [kRegionAutoId] fallback to default catalog item.
  Future<String> pickBestNodeId(List<VpnNode> catalog) async {
    final candidates = catalog
        .where((n) => n.isConnected || n.isDefault)
        .where((n) => n.host.isNotEmpty)
        .toList();
    if (candidates.isEmpty) {
      return kRegionAutoId;
    }
    if (candidates.length == 1) {
      return candidates.first.id;
    }

    String? bestId;
    int bestMs = 1 << 30;

    await Future.wait(
      candidates.map((node) async {
        final ms = await _probeMs(node.host);
        if (ms == null) return;
        if (ms < bestMs) {
          bestMs = ms;
          bestId = node.id;
        }
      }),
    );

    return bestId ?? candidates.firstWhere((n) => n.isDefault, orElse: () => candidates.first).id;
  }

  Future<int?> _probeMs(String host) async {
    final sw = Stopwatch()..start();
    try {
      final socket = await Socket.connect(host, probePort, timeout: timeout);
      await socket.close();
      sw.stop();
      return sw.elapsedMilliseconds;
    } catch (_) {
      return null;
    }
  }
}

/// Resolve API node_id for connect/fetch: auto → latency pick, else stored id.
Future<String?> resolveNodeIdForConfig({
  required String? storedId,
  required List<VpnNode> catalog,
  NodeAutoSelector selector = const NodeAutoSelector(),
}) async {
  if (storedId == null || storedId.isEmpty || storedId == kRegionAutoId) {
    final picked = await selector.pickBestNodeId(catalog);
    if (picked == kRegionAutoId) return null;
    return picked;
  }
  return storedId;
}
