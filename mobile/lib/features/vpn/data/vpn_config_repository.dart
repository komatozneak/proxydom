import 'package:dio/dio.dart';

import '../../../core/api_client.dart';
import 'vpn_config.dart';

/// Repository для `GET /api/v1/vpn/config`.
///
/// Кеширует результат в памяти через [VpnConfigCache]. JWT interceptor
/// на [ApiClient.instance] уже подключён — refresh токена происходит
/// автоматически при 401.
class VpnConfigRepository {
  VpnConfigRepository();

  final Dio _dio = ApiClient.instance;
  final VpnConfigCache _cache = VpnConfigCache.instance;

  /// Получить конфиг. По умолчанию — cache-first.
  ///
  /// Если [forceRefresh] — игнорирует кеш и всегда делает сетевой запрос.
  Future<VpnConfig> getConfig({bool forceRefresh = false}) async {
    if (!forceRefresh && _cache.current != null) {
      return _cache.current!;
    }

    try {
      final resp = await _dio.get<Map<String, dynamic>>('/vpn/config');
      if (resp.statusCode == 200 && resp.data != null) {
        final config = VpnConfig.fromJson(resp.data!);
        _cache.set(config);
        return config;
      }
      throw DioException(
        requestOptions: resp.requestOptions,
        response: resp,
        error: 'Unexpected status: ${resp.statusCode}',
      );
    } on DioException {
      rethrow;
    } catch (e, st) {
      throw DioException(
        requestOptions: RequestOptions(path: '/vpn/config'),
        error: e,
        stackTrace: st,
      );
    }
  }

  /// Очистить кеш (например, после logout или смены юзера).
  void clearCache() => _cache.clear();
}