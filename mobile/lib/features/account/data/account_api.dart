import 'package:dio/dio.dart';

import '../../../core/api_client.dart';
import 'account_profile.dart';

/// Account hub + contact link API.
class AccountApi {
  AccountApi({Dio? dio}) : _dio = dio ?? ApiClient.instance;

  final Dio _dio;

  Future<AccountProfile> fetchMe() async {
    final resp = await _dio.get<Map<String, dynamic>>('/me');
    final data = resp.data;
    if (data == null) {
      throw DioException(
        requestOptions: resp.requestOptions,
        error: 'Empty /me response',
      );
    }
    return AccountProfile.fromJson(data);
  }

  Future<({String deepLink, String token})> startTelegramLink() async {
    final resp = await _dio.post<Map<String, dynamic>>(
      '/auth/contact/telegram/start',
    );
    final data = resp.data ?? const {};
    return (
      deepLink: data['deep_link'] as String? ?? '',
      token: data['token'] as String? ?? '',
    );
  }

  Future<({String token, String? debugCode})> startEmailLink(String email) async {
    final resp = await _dio.post<Map<String, dynamic>>(
      '/auth/contact/email/start',
      data: {'email': email},
    );
    final data = resp.data ?? const {};
    return (
      token: data['token'] as String? ?? '',
      debugCode: data['debug_code'] as String?,
    );
  }

  Future<AccountProfile> verifyEmailLink({
    required String token,
    required String code,
  }) async {
    final resp = await _dio.post<Map<String, dynamic>>(
      '/auth/contact/email/verify',
      data: {'token': token, 'code': code},
    );
    final data = resp.data;
    if (data == null) {
      throw DioException(
        requestOptions: resp.requestOptions,
        error: 'Empty verify response',
      );
    }
    return AccountProfile.fromJson(data);
  }
}
