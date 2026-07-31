/// Response from GET /api/v1/beta/entitlement.
///
/// Server remains authoritative. When [betaPromoGateEnabled] is false the
/// backend still auto-grants alpha, so [hasAccess] should normally be true.
class BetaEntitlement {
  const BetaEntitlement({
    required this.hasAccess,
    required this.betaPromoGateEnabled,
    this.plan,
    this.isAlpha = false,
  });

  final bool hasAccess;
  final bool betaPromoGateEnabled;
  final String? plan;
  final bool isAlpha;

  /// Gate advertises promo entry for authenticated users without access.
  /// When gate is ON, missing entitlement MUST show promo (no soft-pass).
  bool get shouldShowPromo => !hasAccess && betaPromoGateEnabled;

  /// Soft-pass ONLY when gate is off (local/CI / pre-cutover auto-alpha era).
  /// When [betaPromoGateEnabled] is true, requires real [hasAccess].
  bool get treatAsEntitled => hasAccess || !betaPromoGateEnabled;

  factory BetaEntitlement.fromJson(Map<String, dynamic> json) {
    // Missing gate flag must NOT default to false (that soft-passes as entitled).
    final gateRaw = json['beta_promo_gate_enabled'];
    if (gateRaw is! bool) {
      throw FormatException(
        'beta_promo_gate_enabled must be bool, got ${gateRaw.runtimeType}',
      );
    }
    // has_access must be explicit bool; missing/null/string → not entitled.
    final accessRaw = json['has_access'];
    if (accessRaw != null && accessRaw is! bool) {
      throw FormatException(
        'has_access must be bool, got ${accessRaw.runtimeType}',
      );
    }
    return BetaEntitlement(
      hasAccess: accessRaw == true,
      betaPromoGateEnabled: gateRaw,
      plan: json['plan'] as String?,
      isAlpha: json['is_alpha'] == true,
    );
  }

  /// Optional server hint (local prefs remain SoT so logout does not replay).
  static bool? onboardingRequiredFromJson(Map<String, dynamic> json) {
    if (!json.containsKey('onboarding_required')) return null;
    return json['onboarding_required'] == true;
  }

  Map<String, dynamic> toJson() => {
        'has_access': hasAccess,
        'beta_promo_gate_enabled': betaPromoGateEnabled,
        if (plan != null) 'plan': plan,
        'is_alpha': isAlpha,
      };

  static const BetaEntitlement entitledGateOff = BetaEntitlement(
    hasAccess: true,
    betaPromoGateEnabled: false,
  );
}
