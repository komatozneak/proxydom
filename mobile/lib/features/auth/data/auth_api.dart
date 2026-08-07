import '../../../core/api_client.dart';
import '../../../core/install_id_storage.dart';

/// Anonymous bootstrap (FEATURE_AUTH_ANONYMOUS).
///
/// Self-serve restore endpoints are disabled — reinstall help is support-only.
class AuthApi {
  AuthApi();

  Future<BootstrapResult> bootstrap({String? clientId}) async {
    final id = clientId ?? await InstallIdStorage.instance.getOrCreate();
    final resp = await ApiClient.postAuth(
      '/auth/bootstrap',
      data: {'client_id': id},
    );
    if (resp.statusCode != 200 || resp.data is! Map) {
      throw Exception('bootstrap failed: ${resp.statusCode}');
    }
    final data = Map<String, dynamic>.from(resp.data as Map);
    return BootstrapResult.fromJson(data);
  }
}

class BootstrapResult {
  const BootstrapResult({
    required this.accessToken,
    required this.refreshToken,
    required this.hasAccess,
    this.recoveryCode,
  });

  final String accessToken;
  final String refreshToken;
  final bool hasAccess;
  final String? recoveryCode;

  factory BootstrapResult.fromJson(Map<String, dynamic> json) {
    return BootstrapResult(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      hasAccess: json['has_access'] as bool? ?? false,
      recoveryCode: json['recovery_code'] as String?,
    );
  }
}
