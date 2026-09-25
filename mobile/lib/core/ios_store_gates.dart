import 'package:flutter/foundation.dart';

/// Store clients are local key importers (ADR 026). Web stays on the account
/// shell. Uses [defaultTargetPlatform] so widget tests can override with
/// [debugDefaultTargetPlatformOverride].
bool get freeKeyClient => !kIsWeb;

/// The phone binary has no cashier. Web is not a store client either.
bool get hideInAppPlategaCheckout => true;

/// Android VpnService can exclude apps. Independent of the cashier hide:
/// the free client still needs «what works without VPN».
bool get androidPerAppSplit {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.android;
}

/// Per-app split (VpnService.Builder) is Android-only; iOS consumer VPN has no
/// equivalent without MDM (ADR 025). Sites use shared prefs → iOS
/// `excludedRoutes` (destination IP), not hyDialer-protect.
bool get iosAppsSplitUnsupported {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.iOS;
}

/// `teremokconnect://ref` landing. Free clients ignore the link.
String get referralLandingPath {
  if (freeKeyClient) return '/home';
  return '/settings/account/promo';
}

/// Routes that would show a paid catalog or an account join.
bool iosFreeClientRouteBlocked(String location) {
  if (!freeKeyClient) return false;
  if (location == '/subscription' ||
      location == '/premium' ||
      location == '/locked' ||
      location == '/promo' ||
      location == '/restore' ||
      location == '/recovery') {
    return true;
  }
  if (location.startsWith('/settings/devices')) return true;
  if (location.startsWith('/settings/account')) return true;
  return false;
}
