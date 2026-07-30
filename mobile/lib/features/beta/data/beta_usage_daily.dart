/// Allowlisted daily aggregate for POST /api/v1/beta/usage/daily.
///
/// Absolute counters for the UTC day. Retries resend the same
/// [clientBatchId] + snapshot so the server can dedupe / take max.
class BetaUsageDailySnapshot {
  const BetaUsageDailySnapshot({
    required this.day,
    required this.appBuild,
    required this.clientBatchId,
    required this.onboardingCompleted,
    required this.connectAttempts,
    required this.connectSuccesses,
    required this.reconnectCount,
    required this.sessionSeconds,
    required this.regionChangeCount,
    required this.accessStatusLoadOkCount,
    required this.diagnosticReportSentCount,
    required this.crashCount,
  });

  /// UTC calendar day `YYYY-MM-DD`.
  final String day;
  final String appBuild;
  final String clientBatchId;
  final bool onboardingCompleted;
  final int connectAttempts;
  final int connectSuccesses;
  final int reconnectCount;
  final int sessionSeconds;
  final int regionChangeCount;
  final int accessStatusLoadOkCount;
  final int diagnosticReportSentCount;
  final int crashCount;

  Map<String, dynamic> toJson() => {
        'day': day,
        'app_build': appBuild,
        'onboarding_completed': onboardingCompleted,
        'connect_attempts': connectAttempts,
        'connect_successes': connectSuccesses,
        'reconnect_count': reconnectCount,
        'session_seconds': sessionSeconds,
        'region_change_count': regionChangeCount,
        'access_status_load_ok_count': accessStatusLoadOkCount,
        'diagnostic_report_sent_count': diagnosticReportSentCount,
        'crash_count': crashCount,
      };

  /// Wire payload for POST /beta/usage/daily (no local-only fields).
  ///
  /// Backend uses monotonic max upsert (`extra=forbid`); [clientBatchId] is
  /// kept only in local prefs for retry bookkeeping.
  Map<String, dynamic> toUploadJson() => toJson();

  factory BetaUsageDailySnapshot.fromJson(Map<String, dynamic> json) {
    return BetaUsageDailySnapshot(
      day: json['day'] as String,
      appBuild: json['app_build'] as String? ?? '',
      clientBatchId: json['client_batch_id'] as String? ?? '',
      onboardingCompleted: json['onboarding_completed'] == true,
      connectAttempts: _nonNeg(json['connect_attempts']),
      connectSuccesses: _nonNeg(json['connect_successes']),
      reconnectCount: _nonNeg(json['reconnect_count']),
      sessionSeconds: _nonNeg(json['session_seconds']),
      regionChangeCount: _nonNeg(json['region_change_count']),
      accessStatusLoadOkCount: _nonNeg(json['access_status_load_ok_count']),
      diagnosticReportSentCount:
          _nonNeg(json['diagnostic_report_sent_count']),
      crashCount: _nonNeg(json['crash_count']),
    );
  }

  static int _nonNeg(Object? raw) {
    final n = raw is int ? raw : int.tryParse('$raw') ?? 0;
    return n < 0 ? 0 : n;
  }
}
