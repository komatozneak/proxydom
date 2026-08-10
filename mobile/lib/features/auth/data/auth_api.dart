import '../../../core/api_client.dart';
import '../../../core/api_secret_storage.dart';
import '../../../core/install_id_storage.dart';
import 'seat_outcome.dart';

/// Device-first auth (ADR 008 / Ogon register) + device slots (list/leave/revoke).
class AuthApi {
  AuthApi();

  Future<RegisterResult> register({
    String? deviceUuid,
    String? platform,
    String? deviceName,
  }) async {
    final id = deviceUuid ?? await InstallIdStorage.instance.getOrCreate();
    final resp = await ApiClient.postAuth(
      '/auth/register',
      data: {
        'device_uuid': id,
        if (platform != null) 'platform': platform,
        if (deviceName != null) 'device_name': deviceName,
      },
    );
    if (resp.statusCode != 200 || resp.data is! Map) {
      throw Exception('register failed: ${resp.statusCode}');
    }
    return RegisterResult.fromJson(Map<String, dynamic>.from(resp.data as Map));
  }

  /// Legacy alias used by older call sites.
  Future<RegisterResult> bootstrap({String? clientId}) =>
      register(deviceUuid: clientId);

  Future<RegisterResult> recover({
    required String recoveryCode,
    String? deviceUuid,
  }) async {
    final id = deviceUuid ?? await InstallIdStorage.instance.getOrCreate();
    final resp = await ApiClient.postAuth(
      '/auth/recover',
      data: {
        'recovery_code': recoveryCode,
        'device_uuid': id,
      },
    );
    if (resp.statusCode != 200 || resp.data is! Map) {
      throw Exception('recover failed: ${resp.statusCode}');
    }
    return RegisterResult.fromJson(Map<String, dynamic>.from(resp.data as Map));
  }

  Future<SeatCodeResult> makeSeatCode({String? deviceUuid, int? ttlSeconds}) async {
    final id = deviceUuid ?? await InstallIdStorage.instance.getOrCreate();
    final resp = await ApiClient.instance.post(
      '/seats/make-code',
      data: {
        'device_uuid': id,
        if (ttlSeconds != null) 'ttl_seconds': ttlSeconds,
      },
    );
    if (resp.statusCode != 200 || resp.data is! Map) {
      throw SeatApiException(
        resp.statusCode ?? 0,
        detail: parseApiDetail(resp.data),
        errorCode: parseApiErrorCode(resp.data),
      );
    }
    final data = Map<String, dynamic>.from(resp.data as Map);
    return SeatCodeResult(
      code: data['code'] as String,
      expiresAt: data['expires_at'] as String?,
    );
  }

  Future<RegisterResult> acceptSeatCode({
    required String code,
    String? deviceUuid,
  }) async {
    final id = deviceUuid ?? await InstallIdStorage.instance.getOrCreate();
    final resp = await ApiClient.instance.post(
      '/seats/accept',
      data: {
        'code': code,
        'device_uuid': id,
        'platform': 'android',
      },
    );
    if (resp.statusCode != 200 || resp.data is! Map) {
      throw SeatApiException(
        resp.statusCode ?? 0,
        detail: parseApiDetail(resp.data),
        errorCode: parseApiErrorCode(resp.data),
      );
    }
    return RegisterResult.fromJson(Map<String, dynamic>.from(resp.data as Map));
  }

  /// Active device slots for the account (`GET /devices?device_id=`).
  Future<DeviceListResult> listDevices({String? deviceUuid}) async {
    final id = deviceUuid ?? await InstallIdStorage.instance.getOrCreate();
    final resp = await ApiClient.instance.get(
      '/devices',
      queryParameters: {'device_id': id},
    );
    if (resp.statusCode != 200 || resp.data is! Map) {
      throw Exception('list devices failed: ${resp.statusCode}');
    }
    return DeviceListResult.fromJson(Map<String, dynamic>.from(resp.data as Map));
  }

  /// Detach this install into a fresh solo account.
  Future<LeaveDeviceResult> leaveDevice({String? deviceUuid}) async {
    final id = deviceUuid ?? await InstallIdStorage.instance.getOrCreate();
    final resp = await ApiClient.instance.post(
      '/devices/leave',
      data: {'device_uuid': id},
    );
    if (resp.statusCode != 200 || resp.data is! Map) {
      throw Exception('leave device failed: ${resp.statusCode}');
    }
    return LeaveDeviceResult.fromJson(Map<String, dynamic>.from(resp.data as Map));
  }

  /// Revoke another install's slot (VPN key stops working).
  Future<void> revokeDevice(int devicePk) async {
    final resp = await ApiClient.instance.delete('/devices/$devicePk');
    if (resp.statusCode != 204 && resp.statusCode != 200) {
      throw Exception('revoke device failed: ${resp.statusCode}');
    }
  }
}

class RegisterResult {
  const RegisterResult({
    required this.accessToken,
    required this.refreshToken,
    required this.hasAccess,
    this.recoveryCode,
    this.apiSecret,
  });

  final String accessToken;
  final String refreshToken;
  final bool hasAccess;
  final String? recoveryCode;
  final String? apiSecret;

  factory RegisterResult.fromJson(Map<String, dynamic> json) {
    return RegisterResult(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      hasAccess: json['has_access'] as bool? ?? false,
      recoveryCode: json['recovery_code'] as String?,
      apiSecret: json['api_secret'] as String?,
    );
  }

  Future<void> persistApiSecret() async {
    final secret = apiSecret?.trim();
    if (secret != null && secret.isNotEmpty) {
      await ApiSecretStorage.instance.save(secret);
    }
  }
}

/// Backward-compatible typedef for older imports.
typedef BootstrapResult = RegisterResult;

class SeatCodeResult {
  const SeatCodeResult({required this.code, this.expiresAt});

  final String code;
  final String? expiresAt;
}

class DeviceListResult {
  const DeviceListResult({
    required this.devices,
    required this.activeCount,
    required this.maxDevices,
  });

  final List<DeviceSlot> devices;
  final int activeCount;
  final int maxDevices;

  factory DeviceListResult.fromJson(Map<String, dynamic> json) {
    final raw = json['devices'];
    final list = <DeviceSlot>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          list.add(DeviceSlot.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    return DeviceListResult(
      devices: list,
      activeCount: (json['active_count'] as num?)?.toInt() ?? list.length,
      maxDevices: (json['max_devices'] as num?)?.toInt() ?? 5,
    );
  }
}

class DeviceSlot {
  const DeviceSlot({
    required this.id,
    required this.status,
    required this.createdAt,
    this.deviceName,
    this.platform,
    this.lastSeenAt,
    this.isCurrent = false,
  });

  final int id;
  final String? deviceName;
  final String? platform;
  final String status;
  final DateTime? lastSeenAt;
  final DateTime createdAt;
  final bool isCurrent;

  factory DeviceSlot.fromJson(Map<String, dynamic> json) {
    DateTime? parseDt(dynamic v) {
      if (v is String && v.isNotEmpty) return DateTime.tryParse(v)?.toLocal();
      return null;
    }

    return DeviceSlot(
      id: (json['id'] as num).toInt(),
      deviceName: json['device_name'] as String?,
      platform: json['platform'] as String?,
      status: json['status'] as String? ?? 'active',
      lastSeenAt: parseDt(json['last_seen_at']),
      createdAt: parseDt(json['created_at']) ?? DateTime.now(),
      isCurrent: json['is_current'] as bool? ?? false,
    );
  }
}

class LeaveDeviceResult {
  const LeaveDeviceResult({
    required this.accessToken,
    required this.refreshToken,
    required this.hasAccess,
    this.recoveryCode,
  });

  final String accessToken;
  final String refreshToken;
  final bool hasAccess;
  final String? recoveryCode;

  factory LeaveDeviceResult.fromJson(Map<String, dynamic> json) {
    return LeaveDeviceResult(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      hasAccess: json['has_access'] as bool? ?? false,
      recoveryCode: json['recovery_code'] as String?,
    );
  }
}
