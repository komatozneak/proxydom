/// Account session snapshot from GET /session and mutation responses (ADR 016).
class AccountSessionSnapshot {
  const AccountSessionSnapshot({
    required this.version,
    required this.accountId,
    required this.tier,
    required this.hasAccess,
    required this.deviceLimit,
    required this.devices,
    this.plan,
    this.telegramUsername,
    this.contactLinked = false,
    this.endsAt,
    this.currentDeviceId,
    this.currentCaps = const [],
    this.apiSecret,
  });

  final int version;
  final int accountId;
  final String? plan;
  final String? telegramUsername;
  final bool contactLinked;
  final String tier;
  final bool hasAccess;
  final DateTime? endsAt;
  final int deviceLimit;
  final int? currentDeviceId;
  final List<String> currentCaps;
  final List<SessionDeviceItem> devices;
  final String? apiSecret;

  bool get manageAccount => currentCaps.contains('manage_account');

  factory AccountSessionSnapshot.fromJson(Map<String, dynamic> json) {
    final account = json['account'];
    final accountMap = account is Map
        ? Map<String, dynamic>.from(account)
        : <String, dynamic>{};
    final ent = accountMap['entitlement'];
    final entMap =
        ent is Map ? Map<String, dynamic>.from(ent) : <String, dynamic>{};
    final device = json['device'];
    final deviceMap = device is Map ? Map<String, dynamic>.from(device) : null;
    final rawDevices = json['devices'];
    final devices = <SessionDeviceItem>[];
    if (rawDevices is List) {
      for (final item in rawDevices) {
        if (item is Map) {
          devices
              .add(SessionDeviceItem.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    DateTime? ends;
    final rawEnds = entMap['ends_at'];
    if (rawEnds is String && rawEnds.isNotEmpty) {
      ends = DateTime.tryParse(rawEnds)?.toLocal();
    }
    return AccountSessionSnapshot(
      version: (json['version'] as num?)?.toInt() ?? 0,
      accountId: (accountMap['id'] as num?)?.toInt() ?? 0,
      plan: accountMap['plan'] as String?,
      telegramUsername: accountMap['telegram_username'] as String?,
      contactLinked: accountMap['contact_linked'] == true,
      tier: (entMap['tier'] as String?) ?? 'free',
      hasAccess: entMap['has_access'] == true,
      endsAt: ends,
      deviceLimit: (accountMap['device_limit'] as num?)?.toInt() ?? 1,
      currentDeviceId: (deviceMap?['id'] as num?)?.toInt(),
      currentCaps: _stringList(deviceMap?['caps']),
      devices: devices,
      apiSecret: json['api_secret'] as String?,
    );
  }

  static List<String> _stringList(Object? raw) {
    if (raw is! List) return const [];
    return raw.map((e) => e.toString()).toList();
  }
}

class SessionDeviceItem {
  const SessionDeviceItem({
    required this.id,
    required this.installId,
    required this.caps,
    required this.isCurrent,
    this.name,
    this.platform,
    this.createdAt,
  });

  final int id;
  final String installId;
  final List<String> caps;
  final bool isCurrent;
  final String? name;
  final String? platform;
  final DateTime? createdAt;

  bool get manageAccount => caps.contains('manage_account');

  factory SessionDeviceItem.fromJson(Map<String, dynamic> json) {
    DateTime? created;
    final raw = json['created_at'];
    if (raw is String && raw.isNotEmpty) {
      created = DateTime.tryParse(raw)?.toLocal();
    }
    return SessionDeviceItem(
      id: (json['id'] as num).toInt(),
      installId: json['install_id'] as String? ?? '',
      caps: AccountSessionSnapshot._stringList(json['caps']),
      isCurrent: json['is_current'] == true,
      name: json['name'] as String?,
      platform: json['platform'] as String?,
      createdAt: created,
    );
  }
}
