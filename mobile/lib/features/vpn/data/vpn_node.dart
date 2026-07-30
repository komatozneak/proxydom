/// VPN egress node from `GET /api/v1/vpn/nodes`.
class VpnNode {
  const VpnNode({
    required this.id,
    required this.label,
    required this.host,
    required this.port,
    required this.status,
    required this.isDefault,
    this.name = '',
  });

  final String id;
  final String label;
  final String host;
  final int port;
  final String status;
  final bool isDefault;
  final String name;

  bool get isConnected => status.toLowerCase() == 'connected';

  factory VpnNode.fromJson(Map<String, dynamic> json) {
    final rawHost = (json['host'] as String?) ?? '';
    // Marzban sometimes sends "ip:port" — keep host-only for pool matching.
    final host = _hostOnly(rawHost);
    return VpnNode(
      id: '${json['id'] ?? host}',
      label: (json['label'] as String?) ?? (json['name'] as String?) ?? '',
      host: host,
      port: (json['port'] as int?) ?? _portFromHost(rawHost) ?? 443,
      status: (json['status'] as String?) ?? 'unknown',
      isDefault: (json['is_default'] as bool?) ?? false,
      name: (json['name'] as String?) ?? '',
    );
  }

  static String _hostOnly(String raw) {
    var h = raw.trim();
    if (h.startsWith('[')) {
      final end = h.indexOf(']');
      if (end > 0) return h.substring(1, end);
    }
    final colon = h.indexOf(':');
    if (colon > 0 && h.indexOf(':', colon + 1) < 0) {
      return h.substring(0, colon);
    }
    return h;
  }

  static int? _portFromHost(String raw) {
    final h = raw.trim();
    final colon = h.indexOf(':');
    if (colon <= 0 || h.indexOf(':', colon + 1) >= 0) return null;
    return int.tryParse(h.substring(colon + 1));
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'host': host,
        'port': port,
        'status': status,
        'is_default': isDefault,
        'name': name,
      };
}
