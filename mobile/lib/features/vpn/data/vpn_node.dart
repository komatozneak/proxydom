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
    return VpnNode(
      id: '${json['id'] ?? json['host']}',
      label: (json['label'] as String?) ?? (json['name'] as String?) ?? '',
      host: json['host'] as String,
      port: (json['port'] as int?) ?? 443,
      status: (json['status'] as String?) ?? 'unknown',
      isDefault: (json['is_default'] as bool?) ?? false,
      name: (json['name'] as String?) ?? '',
    );
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
