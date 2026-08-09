import '../../../core/api_client.dart';
import '../../../core/api_secret_storage.dart';
import '../../../core/install_id_storage.dart';

/// Device-first auth (ADR 008 / Ogon register).
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
      throw Exception('make-code failed: ${resp.statusCode}');
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
      throw Exception('accept failed: ${resp.statusCode}');
    }
    return RegisterResult.fromJson(Map<String, dynamic>.from(resp.data as Map));
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
