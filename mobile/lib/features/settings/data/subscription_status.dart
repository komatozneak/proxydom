/// Subscription status from GET /api/v1/billing/subscription.
class SubscriptionStatus {
  const SubscriptionStatus({
    this.plan,
    this.status,
    this.startedAt,
    this.expiresAt,
    this.autoRenew = false,
    this.amountRub,
    this.isPro = false,
    this.isTrial = false,
    this.isAlpha = false,
    this.daysRemaining,
    this.quotaBytesUsed,
    this.quotaBytesLimit,
    this.quotaBytesRemaining,
    this.quotaUnlimited = false,
  });

  final String? plan;
  final String? status;
  final DateTime? startedAt;
  final DateTime? expiresAt;
  final bool autoRenew;
  final double? amountRub;
  final bool isPro;
  final bool isTrial;
  final bool isAlpha;
  final int? daysRemaining;
  final int? quotaBytesUsed;
  final int? quotaBytesLimit;
  final int? quotaBytesRemaining;
  final bool quotaUnlimited;

  bool get hasActivePaid => isPro && status == 'active';

  bool get isEmpty => plan == null && status == null;

  /// Free tier with no remaining server-metered bytes (ADR 013).
  bool get quotaExhausted =>
      !quotaUnlimited &&
      quotaBytesRemaining != null &&
      quotaBytesRemaining! <= 0 &&
      (quotaBytesLimit ?? 0) > 0;

  factory SubscriptionStatus.fromJson(Map<String, dynamic> json) {
    DateTime? parseDt(Object? v) {
      if (v is! String || v.isEmpty) return null;
      return DateTime.tryParse(v)?.toLocal();
    }

    final plan = json['plan'] as String?;
    final isAlpha = json['is_alpha'] as bool? ?? plan == 'alpha';

    return SubscriptionStatus(
      plan: plan,
      status: json['status'] as String?,
      startedAt: parseDt(json['started_at']),
      expiresAt: parseDt(json['expires_at']),
      autoRenew: json['auto_renew'] as bool? ?? false,
      amountRub: (json['amount_rub'] as num?)?.toDouble(),
      isPro: json['is_pro'] as bool? ?? false,
      isTrial: json['is_trial'] as bool? ?? false,
      isAlpha: isAlpha,
      daysRemaining: (json['days_remaining'] as num?)?.toInt(),
      quotaBytesUsed: (json['quota_bytes_used'] as num?)?.toInt(),
      quotaBytesLimit: (json['quota_bytes_limit'] as num?)?.toInt(),
      quotaBytesRemaining: (json['quota_bytes_remaining'] as num?)?.toInt(),
      quotaUnlimited: json['quota_unlimited'] as bool? ?? false,
    );
  }

  static const empty = SubscriptionStatus();
}
