import '../data/subscription_status.dart';

/// Which Access tile strings to show for a [SubscriptionStatus] payload.
///
/// Closed-beta redeem grants an active `plan=alpha` / `is_alpha` row — that is
/// invite entitlement, not the Free cold-start tier.
enum AccessCopyKind {
  paidOrTrial,
  cancelled,
  closedBeta,
  free,
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
  // Free cold auth: empty / no subscription row → Free tier copy.
  if (s.isEmpty) return AccessCopyKind.free;
  return AccessCopyKind.generic;
}
