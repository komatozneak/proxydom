import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api_client.dart';
import '../../../core/vpn_nodes.dart';
import 'vpn_node.dart';

const _selectedNodeKey = SelectedRegionStore.key;

/// Repository for node catalog + local selection persistence.
///
/// Uses `GET /api/v1/vpn/nodes` (local default + remote workers + labels).
class VpnNodesRepository {
  VpnNodesRepository();

  final Dio _dio = ApiClient.instance;

  Future<List<VpnNode>> listNodes() async {
    // Full catalog (local + workers + labels) — not only /nodes workers.
    final resp = await _dio.get<Map<String, dynamic>>('/vpn/nodes');
    final raw = resp.data?['nodes'];
    if (raw is! List) {
      return const [];
    }
    return raw
        .whereType<Map>()
        .map((e) => VpnNode.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<String?> getSelectedNodeId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_selectedNodeKey);
  }

  Future<void> setSelectedNodeId(String nodeId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectedNodeKey, nodeId);
  }

  Future<void> clearSelectedNodeId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_selectedNodeKey);
  }
}
