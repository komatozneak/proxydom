/// Application configuration.
///
/// ## Dev vs prod backend
///
/// [baseUrl] defaults to [vpsBaseUrl] for production.
/// Emulator: `flutter run --dart-define=APP_ENV=dev`
///
/// ## Platform dev URLs
///
/// - Android emulator: [androidBaseUrl] (`http://10.0.2.2:8000/api/v1`)
/// - Physical Android: `adb reverse tcp:8000 tcp:8000` + `http://127.0.0.1:8000`
/// - iOS simulator: [iosBaseUrl]
/// - Desktop: [desktopBaseUrl]
class AppConfig {
  AppConfig._();

  /// Production API origin (scheme + host, no path).
  static const String vpsApiOrigin = 'https://api.proxydom.su';

  /// Production API. The hub serves `/api/v1`; `/v2` is not routed.
  static const String vpsBaseUrl = '$vpsApiOrigin/api/v1';

  /// Seed hosts for discovery failover (own domains only — not Огонь .xyz).
  static const List<String> discoverySeedHosts = [
    'https://api.proxydom.su',
    'https://api2.proxydom.su',
  ];

  /// Hostname for the RF control-plane API (no scheme / path).
  static const String vpsHostname = 'api.proxydom.su';

  /// Compile-time override for the control-plane A-record used by TUN
  /// `excludeRoute` and engine DNS `hosts` pin. Empty → [vpsIpv4Fallback].
  ///
  /// Override: `--dart-define=VPS_CONTROL_PLANE_IPV4=1.2.3.4`
  static const String _vpsControlPlaneIpv4Override = String.fromEnvironment(
    'VPS_CONTROL_PLANE_IPV4',
    defaultValue: '',
  );

  /// Last-known good A-record for [vpsHostname] (API host, 195.225.108.81).
  /// Prefer override / DNS resolution at runtime where available; this is the
  /// offline fallback so TUN bypass and engine hosts pin stay valid if DNS fails
  /// under VPN. Must match the live `api.proxydom.su` A-record.
  static const String vpsIpv4Fallback = '195.225.108.81';

  /// Effective control-plane IPv4 for routing / DNS hosts pin.
  static String get vpsControlPlaneIpv4 {
    final override = _vpsControlPlaneIpv4Override.trim();
    if (override.isNotEmpty) return override;
    return vpsIpv4Fallback;
  }

  /// Alias kept for existing call sites (TUN exclude, Dio happy-eyeballs).
  static String get vpsIpv4 => vpsControlPlaneIpv4;

  /// Dev API base URL — Android emulator.
  static const String androidBaseUrl = 'http://10.0.2.2:8000/api/v1';
  static const String iosBaseUrl = 'http://127.0.0.1:8000/api/v1';
  static const String desktopBaseUrl = 'http://localhost:8000/api/v1';

  /// Compile-time env: `prod` (default на физ. устройстве) или `dev` (эмулятор).
  /// Эмулятор: `flutter run --dart-define=APP_ENV=dev`
  static const String _appEnv = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'prod',
  );

  /// Optional build-time endpoint for physical-device contract verification.
  static const String _baseUrlOverride = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  /// Active base URL. Production builds use [vpsBaseUrl] unless explicitly
  /// overridden by a developer build.
  static const String baseUrl = _baseUrlOverride != ''
      ? _baseUrlOverride
      : (_appEnv == 'prod' ? vpsBaseUrl : androidBaseUrl);

  /// Resolve base URL for a given env label (used in tests).
  static String baseUrlForEnvironment(String appEnv) =>
      appEnv == 'prod' ? vpsBaseUrl : androidBaseUrl;

  /// Strip `/v2` or `/api/v1` suffix to get scheme+host+port.
  static String resolveApiOrigin(String url) {
    var u = url.trim().replaceAll(RegExp(r'/+$'), '');
    for (final suffix in ['/api/v1', '/v2']) {
      if (u.endsWith(suffix)) {
        u = u.substring(0, u.length - suffix.length);
        break;
      }
    }
    return u;
  }

  /// Build the API base URL for [origin].
  static String baseUrlForOrigin(String origin) {
    final o = origin.trim().replaceAll(RegExp(r'/+$'), '');
    return '$o/api/v1';
  }

  /// Таймаут dio по умолчанию.
  /// Auth/bootstrap requests may be slower on mobile networks, so keep headroom.
  static const Duration connectTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 60);

  /// Longer timeout budget for bootstrap/recovery auth endpoints.
  static const Duration authConnectTimeout = Duration(seconds: 45);
  static const Duration authReceiveTimeout = Duration(seconds: 90);

  /// Anonymous UUID cold start. Pair with backend
  /// `FEATURE_AUTH_ANONYMOUS=true`.
  static const bool authAnonymous = bool.fromEnvironment(
    'AUTH_ANONYMOUS',
    defaultValue: true,
  );

  /// Bank / Play review — public legal pages (always-on footer).
  static const String privacyPolicyUrl = 'https://proxydom.su/privacy.html';

  static const String termsOfServiceUrl = 'https://proxydom.su/terms.html';

  static const String supportPageUrl = 'https://proxydom.su/support.html';

  /// Role contact shown in the app. Matches the site footer and the mailbox
  /// the Apple and D&B correspondence runs on.
  static const String supportEmail = 'support@proxydom.su';
}
