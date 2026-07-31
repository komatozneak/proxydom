import '../data/beta_entitlement.dart';
import '../../onboarding/data/onboarding_prefs.dart';

/// Post-auth destinations after Flash Call (or cold restore).
enum PostAuthDestination {
  promo,
  onboarding,
  home,
}

/// Pure routing decision — unit-tested without Flutter.
class PostAuthRouter {
  const PostAuthRouter._();

  static PostAuthDestination resolve({
    required BetaEntitlement entitlement,
    required bool onboardingCompleted,
  }) {
    // Closed beta: gate ON + no access → promo. No other path may invent access.
    if (entitlement.betaPromoGateEnabled && !entitlement.hasAccess) {
      return PostAuthDestination.promo;
    }
    if (entitlement.shouldShowPromo) {
      return PostAuthDestination.promo;
    }
    // Soft-pass ONLY when server explicitly set beta_promo_gate_enabled=false.
    // Network errors / missing fields never reach here (gate screen retries).
    if (!entitlement.treatAsEntitled) {
      return PostAuthDestination.promo;
    }
    if (!onboardingCompleted) {
      return PostAuthDestination.onboarding;
    }
    return PostAuthDestination.home;
  }

  static Future<PostAuthDestination> resolveWithPrefs({
    required BetaEntitlement entitlement,
    required String userId,
  }) async {
    final done = await OnboardingPrefs.isCompleted(userId: userId);
    return resolve(entitlement: entitlement, onboardingCompleted: done);
  }
}
