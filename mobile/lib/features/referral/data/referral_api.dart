import 'package:dio/dio.dart';

import '../../../core/api_client.dart';

class ReferralBindResult {
  const ReferralBindResult({
    required this.outcome,
    this.trialGranted = false,
    this.hasAccess = false,
  });

  final String outcome;
  final bool trialGranted;
  final bool hasAccess;

  bool get accepted =>
      outcome == 'bound' || outcome == 'already_bound';

  factory ReferralBindResult.fromJson(Map<String, dynamic> json) {
    return ReferralBindResult(
      outcome: json['outcome'] as String? ?? 'invalid',
      trialGranted: json['trial_granted'] == true,
      hasAccess: json['has_access'] == true,
    );
  }
}

class ReferralMe {
  const ReferralMe({
    required this.enabled,
    this.personalCode,
    this.shareUrl,
  });

  final bool enabled;
  final String? personalCode;
  final String? shareUrl;

  factory ReferralMe.fromJson(Map<String, dynamic> json) {
    return ReferralMe(
      enabled: json['enabled'] == true,
      personalCode: json['personal_code'] as String?,
      shareUrl: json['share_url'] as String?,
    );
  }
}

class ReferralApi {
  ReferralApi({Dio? dio}) : _dio = dio ?? ApiClient.instance;

  final Dio _dio;

  Future<ReferralBindResult?> bind(String code) async {
    try {
      final resp = await _dio.post<Map<String, dynamic>>(
        '/referral/bind',
        data: {'code': code.trim(), 'source': 'app'},
      );
      final raw = resp.data;
      if (raw == null) return null;
      return ReferralBindResult.fromJson(raw);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<ReferralMe?> fetchMe() async {
    try {
      final resp = await _dio.get<dynamic>('/referral/me');
      if (resp.statusCode != 200 || resp.data is! Map) return null;
      return ReferralMe.fromJson(Map<String, dynamic>.from(resp.data as Map));
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      return null;
    }
  }
}
