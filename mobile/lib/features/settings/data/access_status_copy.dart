import '../data/subscription_status.dart';

/// Which Access tile strings to show for a [SubscriptionStatus] payload.
///
/// Closed-beta redeem grants an active `plan=alpha` / `is_alpha` row — that is
/// invite entitlement, not the old open «early access» alpha era.
enum AccessCopyKind {
  paidOrTrial,
  cancelled,
  closedBeta,
  none,
  generic,
}

/// Maps GET /billing/subscription fields → Access copy kind (pure, testable).
AccessCopyKind accessCopyKind(SubscriptionStatus s) {
  if (s.hasActivePaid || s.isTrial) return AccessCopyKind.paidOrTrial;
  if (s.isAlpha) return AccessCopyKind.closedBeta;
  if (s.status == 'cancelled' && s.expiresAt != null) {
    return AccessCopyKind.cancelled;
  }
  if (s.isEmpty) return AccessCopyKind.none;
  return AccessCopyKind.generic;
}
