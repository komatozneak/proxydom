/// Stable machine outcomes from POST /api/v1/beta/redeem.
enum BetaRedeemOutcomeCode {
  redeemed,
  alreadyRedeemed,
  alreadyHasAccess,
  invalid,
  expired,
  exhausted,
  revoked,
  rateLimited,
  unknown;

  static BetaRedeemOutcomeCode fromWire(String? raw) {
    return switch (raw) {
      'redeemed' => BetaRedeemOutcomeCode.redeemed,
      'already_redeemed' => BetaRedeemOutcomeCode.alreadyRedeemed,
      'already_has_access' => BetaRedeemOutcomeCode.alreadyHasAccess,
      'invalid' => BetaRedeemOutcomeCode.invalid,
      'expired' => BetaRedeemOutcomeCode.expired,
      'exhausted' => BetaRedeemOutcomeCode.exhausted,
      'revoked' => BetaRedeemOutcomeCode.revoked,
      'rate_limited' => BetaRedeemOutcomeCode.rateLimited,
      _ => BetaRedeemOutcomeCode.unknown,
    };
  }

  bool get isSuccess =>
      this == BetaRedeemOutcomeCode.redeemed ||
      this == BetaRedeemOutcomeCode.alreadyRedeemed ||
      this == BetaRedeemOutcomeCode.alreadyHasAccess;
}

class BetaRedeemResult {
  const BetaRedeemResult({
    required this.outcome,
    this.hasAccess = false,
    this.acquisitionSource,
    this.recoveryCode,
  });

  final BetaRedeemOutcomeCode outcome;
  final bool hasAccess;
  final String? acquisitionSource;
  final String? recoveryCode;

  factory BetaRedeemResult.fromJson(Map<String, dynamic> json) {
    final wire = (json['outcome'] ?? json['code'])?.toString();
    return BetaRedeemResult(
      outcome: BetaRedeemOutcomeCode.fromWire(wire),
      hasAccess: json['has_access'] == true,
      acquisitionSource: json['acquisition_source'] as String?,
      recoveryCode: json['recovery_code'] as String?,
    );
  }
}
