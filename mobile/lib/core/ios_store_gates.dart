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
/// equivalent without MDM. Sites/domain split may still apply via shared prefs.
bool get iosAppsSplitUnsupported {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.iOS;
}
