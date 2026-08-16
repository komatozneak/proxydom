/// One occupied slot shown when restore hits the Premium device cap.
class RestoreDeviceChoice {
  const RestoreDeviceChoice({
    required this.id,
    required this.name,
    this.lastSeen,
    required this.isOwner,
  });

  final int id;
  final String name;
  final String? lastSeen;
  final bool isOwner;

  factory RestoreDeviceChoice.fromJson(Map<String, dynamic> json) {
    return RestoreDeviceChoice(
      id: (json['id'] as num).toInt(),
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? (json['name'] as String).trim()
          : 'Device',
      lastSeen: json['last_seen'] as String?,
      isOwner: json['is_owner'] == true,
    );
  }

  static List<RestoreDeviceChoice> listFrom(dynamic raw) {
    if (raw is! List) return const [];
    final out = <RestoreDeviceChoice>[];
    for (final item in raw) {
      if (item is Map) {
        out.add(RestoreDeviceChoice.fromJson(Map<String, dynamic>.from(item)));
      }
    }
    return out;
  }

  /// FastAPI 409 `{detail: {devices: [...]}}` or poll `{devices: [...]}`.
  static List<RestoreDeviceChoice> listFromResponse(dynamic data) {
    if (data is! Map) return const [];
    final map = Map<String, dynamic>.from(data);
    if (map['devices'] is List) {
      return listFrom(map['devices']);
    }
    final detail = map['detail'];
    if (detail is Map && detail['devices'] is List) {
      return listFrom(detail['devices']);
    }
    return const [];
  }
}

/// Recovery-code restore stopped so the person can pick which slot to drop.
class NeedsDeviceSlotException implements Exception {
  NeedsDeviceSlotException(this.devices);

  final List<RestoreDeviceChoice> devices;

  @override
  String toString() => 'NeedsDeviceSlotException(${devices.length} devices)';
}
