import 'package:dio/dio.dart';

import '../../../core/api_client.dart';
import 'account_profile.dart';

/// Account hub API (`GET /me` only — no contact link).
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
}
