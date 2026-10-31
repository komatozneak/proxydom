import 'package:flutter/foundation.dart';

/// Uses [defaultTargetPlatform] so widget tests can override with
/// [debugDefaultTargetPlatformOverride].

/// Android VpnService can exclude apps. The utility still needs
/// «what works without VPN».
bool get androidPerAppSplit {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.android;
}

/// Per-app split (VpnService.Builder) is Android-only; iOS consumer VPN has no
/// equivalent without MDM. Sites use shared prefs → iOS
/// `excludedRoutes` (destination IP), not hyDialer-protect.
bool get iosAppsSplitUnsupported {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.iOS;
}

/// Windows desktop utility. Same screens as the phone.
bool get windowsDesktop {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.windows;
}

/// Who restores a dropped tunnel.
///
/// Android `VpnService` (Always-on / on-demand) and the iOS Packet Tunnel bring
/// the session back on their own, so a second Flutter connect would only race
/// that restore. The Windows service tears the tunnel down and hands the route
/// back (it never reconnects itself), so the app layer owns recovery there.
bool get nativeOwnsTunnelRecovery {
  if (kIsWeb) return false;
  return !windowsDesktop;
}

/// Apps tab stays on Android. iOS and Windows show sites only.
bool get sitesOnlySplit => iosAppsSplitUnsupported || windowsDesktop;
