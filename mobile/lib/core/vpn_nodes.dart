import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import '../features/vpn/data/vpn_node.dart';

/// Catalog from `GET /api/v1/nodes` (connected Marzban workers).
class VpnNodesApi {
  VpnNodesApi();

  final Dio _dio = ApiClient.instance;

  Future<List<VpnNode>> listConnectedNodes() async {
    final resp = await _dio.get<Map<String, dynamic>>('/nodes');
    final raw = resp.data?['nodes'];
    if (raw is! List) {
      return const [];
    }
    return raw.whereType<Map>().map((e) {
      final m = Map<String, dynamic>.from(e);
      return VpnNode(
        id: '${m['id'] ?? m['name'] ?? ''}',
        label: (m['name'] as String?) ?? (m['address'] as String?) ?? '',
        host: (m['address'] as String?) ?? '',
        port: (m['port'] as int?) ?? 443,
        status: (m['status'] as String?) ?? 'unknown',
        isDefault: false,
        name: (m['name'] as String?) ?? '',
      );
    }).toList();
  }
}

/// Persists the Region picker selection.
class SelectedRegionStore {
  static const key = 'selected_region_id';

  Future<String?> get() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  Future<void> set(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, id);
  }
}
