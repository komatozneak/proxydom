import 'package:dio/dio.dart';

import '../../../core/api_client.dart';
import 'beta_entitlement.dart';
import 'beta_redeem_outcome.dart';
import 'beta_usage_daily.dart';

/// Thin client for closed-beta endpoints (leading-slash Dio paths).
class BetaApi {
  BetaApi({Dio? dio}) : _dio = dio ?? ApiClient.instance;

  final Dio _dio;

  Future<BetaEntitlement> fetchEntitlement() async {
    // Untyped get avoids Dio's post-interceptor `as Map<String,dynamic>` throw
    // (surfaces as DioExceptionType.unknown with empty message).
    final resp = await _dio.get<dynamic>('/beta/entitlement');
    // 401 must NOT soft-pass as gate-off (treatAsEntitled would become true).
    if (resp.statusCode == 401) {
      throw DioException(
        requestOptions: resp.requestOptions,
        response: resp,
        type: DioExceptionType.badResponse,
        message: 'beta entitlement unauthorized',
      );
    }
    if (resp.statusCode != 200 || resp.data == null) {
      throw DioException(
        requestOptions: resp.requestOptions,
        response: resp,
        message: 'beta entitlement failed: ${resp.statusCode}',
      );
    }
    final raw = resp.data;
    if (raw is! Map) {
      throw DioException(
        requestOptions: resp.requestOptions,
        response: resp,
        message: 'beta entitlement bad body type: ${raw.runtimeType}',
      );
    }
    return BetaEntitlement.fromJson(Map<String, dynamic>.from(raw));
  }

  Future<BetaRedeemResult> redeem(String code) async {
    final resp = await _dio.post<Map<String, dynamic>>(
      '/beta/redeem',
      data: {'code': code.trim()},
    );
    if (resp.statusCode == 429) {
      return const BetaRedeemResult(outcome: BetaRedeemOutcomeCode.rateLimited);
    }
    final raw = resp.data;
    if (raw == null) {
      return const BetaRedeemResult(outcome: BetaRedeemOutcomeCode.unknown);
    }
    return BetaRedeemResult.fromJson(raw);
  }

  /// Fire-and-forget friendly: throws on hard failure so caller can retry.
  Future<void> uploadUsageDaily(BetaUsageDailySnapshot snapshot) async {
    final resp = await _dio.post<Map<String, dynamic>>(
      '/beta/usage/daily',
      data: snapshot.toUploadJson(),
    );
    if (resp.statusCode == null ||
        resp.statusCode! < 200 ||
        resp.statusCode! >= 300) {
      throw DioException(
        requestOptions: resp.requestOptions,
        response: resp,
        message: 'beta usage daily failed: ${resp.statusCode}',
      );
    }
  }
}
