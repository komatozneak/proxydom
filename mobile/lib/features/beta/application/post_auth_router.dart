import '../data/beta_entitlement.dart';
import '../../onboarding/data/onboarding_prefs.dart';
import '../../../core/config.dart';

/// Post-auth destinations after Flash Call / anonymous bootstrap.
enum PostAuthDestination {
  promo,
  locked,
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
    final anonymous =
        AppConfig.authAnonymous || entitlement.authAnonymousEnabled;

    // Free cold auth (ADR 010): anonymous without Premium still enters the app.
    // Seats / premium nodes stay gated by entitlement; VPN uses free quota.
    if (anonymous) {
      if (!onboardingCompleted) {
        return PostAuthDestination.onboarding;
      }
      return PostAuthDestination.home;
    }

    // Legacy phone / closed-beta promo path.
    if (entitlement.betaPromoGateEnabled && !entitlement.hasAccess) {
      return PostAuthDestination.promo;
    }
    if (entitlement.shouldShowPromo) {
      return PostAuthDestination.promo;
    }
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
