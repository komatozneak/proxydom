import 'package:dio/dio.dart';

import '../../../core/api_client.dart';
import 'device_envelope.dart';
import 'vpn_config.dart';

/// Repository для `GET /api/v1/vpn/config`.
///
/// Кеширует результат в памяти через [VpnConfigCache]. JWT interceptor
/// на [ApiClient.instance] уже подключён — refresh токена происходит
/// автоматически при 401.
///
/// Always sends device envelope (install id). Backend ignores it when
/// FEATURE_DEVICE_SLOTS=false; when true, registers/uses a per-device slot.
class VpnConfigRepository {
  VpnConfigRepository();

  final Dio _dio = ApiClient.instance;
  final VpnConfigCache _cache = VpnConfigCache.instance;

  /// Получить конфиг. По умолчанию — cache-first.
  ///
  /// Если [forceRefresh] — игнорирует кеш и всегда делает сетевой запрос.
  /// [nodeId] selects Marzban multi-node egress (`?node_id=`).
  Future<VpnConfig> getConfig({
    bool forceRefresh = false,
    String? nodeId,
  }) async {
    if (!forceRefresh && nodeId == null && _cache.current != null) {
      return _cache.current!;
    }

    try {
      final envelope = await buildDeviceEnvelope();
      final resp = await _dio.get<Map<String, dynamic>>(
        '/vpn/config',
        queryParameters: {
          ...envelope.toQueryParameters(),
          if (nodeId != null && nodeId.isNotEmpty) 'node_id': nodeId,
        },
      );
      if (resp.statusCode == 200 && resp.data != null) {
        final config = VpnConfig.fromJson(resp.data!);
        _cache.set(config);
        return config;
      }
      throw DioException(
        requestOptions: resp.requestOptions,
        response: resp,
        type: DioExceptionType.badResponse,
        error: 'Unexpected status: ${resp.statusCode}',
      );
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final detail = e.response?.data;
      if (code == 403 && detail is Map) {
        final err = detail['detail'];
        if (err is Map && err['error'] is Map) {
          final nested = err['error'] as Map;
          if (nested['code'] == 'device_limit_reached') {
            throw DioException(
              requestOptions: e.requestOptions,
              response: e.response,
              type: DioExceptionType.badResponse,
              error: 'device_limit_reached',
            );
          }
          if (nested['code'] == 'device_revoked') {
            throw DioException(
              requestOptions: e.requestOptions,
              response: e.response,
              type: DioExceptionType.badResponse,
              error: 'device_revoked',
            );
          }
        }
      }
      if ((code == 502 || code == 503) && detail is Map) {
        final err = detail['detail'];
        if (err is Map && err['error'] is Map) {
          final nested = err['error'] as Map;
          final apiCode = nested['code'];
          if (apiCode == 'tt_provision_failed') {
            throw DioException(
              requestOptions: e.requestOptions,
              response: e.response,
              type: DioExceptionType.badResponse,
              error: 'tt_provision_failed',
            );
          }
          if (apiCode == 'provision_pending') {
            throw DioException(
              requestOptions: e.requestOptions,
              response: e.response,
              type: DioExceptionType.badResponse,
              error: 'provision_pending',
            );
          }
        }
      }
      // ADR 012: structured HMAC 401 → cold register.
      if (code == 401 && detail is Map) {
        final err = detail['detail'];
        if (err is Map && err['error'] is Map) {
          final nested = err['error'] as Map;
          if (nested['code'] == 'hmac_required') {
            throw DioException(
              requestOptions: e.requestOptions,
              response: e.response,
              type: DioExceptionType.badResponse,
              error: 'hmac_required',
            );
          }
        }
      }
      rethrow;
    } catch (e, st) {
      if (e is DioException) rethrow;
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
