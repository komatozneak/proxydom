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
    // Soft-pass ONLY when server says gate is off. Gate ON + !hasAccess → promo.
    if (entitlement.betaPromoGateEnabled && !entitlement.hasAccess) {
      return PostAuthDestination.promo;
    }
    if (entitlement.shouldShowPromo) {
      return PostAuthDestination.promo;
    }
    // Gate off + no access: soft-pass (server still auto-alphas when gate false).
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
