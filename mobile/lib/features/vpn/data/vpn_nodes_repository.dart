import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api_client.dart';
import '../../../core/vpn_nodes.dart';
import 'vpn_node.dart';

const _selectedNodeKey = SelectedRegionStore.key;
const _nodesCacheKey = 'vpn_nodes_cache_v1';

/// Repository for node catalog + local selection persistence.
///
/// Uses `GET /api/v1/vpn/nodes` (local default + remote workers + labels).
class VpnNodesRepository {
  VpnNodesRepository();

  final Dio _dio = ApiClient.instance;

  Future<List<VpnNode>> listNodes({bool allowCacheFallback = true}) async {
    try {
      final nodes = await _fetchRemote();
      await _saveCache(nodes);
      return nodes;
    } catch (e) {
      if (allowCacheFallback) {
        final cached = await loadCachedNodes();
        if (cached != null && cached.isNotEmpty) {
          return cached;
        }
      }
      rethrow;
    }
  }

  /// Same as [listNodes], but reports whether the catalog came from disk cache.
  Future<({List<VpnNode> nodes, bool fromCache})> listNodesDetailed({
    bool allowCacheFallback = true,
  }) async {
    try {
      final nodes = await _fetchRemote();
      await _saveCache(nodes);
      return (nodes: nodes, fromCache: false);
    } catch (e) {
      if (allowCacheFallback) {
        final cached = await loadCachedNodes();
        if (cached != null && cached.isNotEmpty) {
          return (nodes: cached, fromCache: true);
        }
      }
      rethrow;
    }
  }

  Future<List<VpnNode>> _fetchRemote() async {
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

  Future<List<VpnNode>?> loadCachedNodes() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_nodesCacheKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      return decoded
          .whereType<Map>()
          .map((e) => VpnNode.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_nodesCacheKey);
  }

  /// Drop disk cache and fetch the catalog for the current entitlement.
  Future<List<VpnNode>> refreshAfterEntitlementChange() async {
    await clearCache();
    return listNodes(allowCacheFallback: false);
  }

  Future<void> _saveCache(List<VpnNode> nodes) async {
    if (nodes.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final payload = jsonEncode(nodes.map((n) => n.toJson()).toList());
    await prefs.setString(_nodesCacheKey, payload);
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
