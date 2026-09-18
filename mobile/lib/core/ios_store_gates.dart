import 'package:flutter/foundation.dart';

/// App Store iOS must not surface Platega hosted checkout (guideline 3.1.1).
/// Android keeps ADR 017 Platega. See [docs/ops/ios-iap-parked.md].
///
/// Uses [defaultTargetPlatform] so widget tests can override with
/// [debugDefaultTargetPlatformOverride].
bool get hideInAppPlategaCheckout {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.iOS;
}

/// Per-app split (VpnService.Builder) is Android-only; iOS consumer VPN has no
/// equivalent without MDM (ADR 025). Sites use shared prefs → iOS
/// `excludedRoutes` (destination IP), not hyDialer-protect.
bool get iosAppsSplitUnsupported {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.iOS;
}

/// `teremokconnect://ref` landing. iOS has no in-app promo cashier.
String get referralLandingPath {
  if (hideInAppPlategaCheckout) return '/settings/account';
  return '/settings/account/promo';
}
