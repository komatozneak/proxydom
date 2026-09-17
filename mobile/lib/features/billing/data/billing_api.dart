import 'package:dio/dio.dart';

import '../../../core/api_client.dart';
import '../../../core/ios_store_gates.dart';

/// Platega hosted checkout (ADR 017): Free Play listing, not Play Billing.
/// Do not add BillingClient / com.android.vending.BILLING.
/// iOS must not call hosted checkout (guideline 3.1.1); see [hideInAppPlategaCheckout].
class BillingApi {
  BillingApi({Dio? dio}) : _dio = dio ?? ApiClient.instance;

  final Dio _dio;

  Future<PlategaCreateResult> createPlategaPayment({required String plan}) async {
    if (hideInAppPlategaCheckout) {
      throw UnsupportedError('in-app checkout is not available');
    }
    final resp = await _dio.post<Map<String, dynamic>>(
      '/billing/platega/create',
      data: {'plan': plan},
    );
    if (resp.statusCode != 200 || resp.data == null) {
      throw DioException(
        requestOptions: resp.requestOptions,
        response: resp,
        message: 'platega create failed: ${resp.statusCode}',
      );
    }
    return PlategaCreateResult.fromJson(resp.data!);
  }
}

class PlategaCreateResult {
  const PlategaCreateResult({
    required this.transactionId,
    required this.redirectUrl,
    required this.amountRub,
    required this.plan,
  });

  final String transactionId;
  final String redirectUrl;
  final double amountRub;
  final String plan;

  factory PlategaCreateResult.fromJson(Map<String, dynamic> json) {
    return PlategaCreateResult(
      transactionId: json['transaction_id'] as String,
      redirectUrl: json['redirect_url'] as String,
      amountRub: (json['amount_rub'] as num).toDouble(),
      plan: json['plan'] as String,
    );
  }
}
