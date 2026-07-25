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

  bool get hasActivePaid => isPro && status == 'active';

  bool get isEmpty => plan == null && status == null;

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
    );
  }

  static const empty = SubscriptionStatus();
}
