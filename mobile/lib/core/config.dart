/// Конфигурация приложения.
///
/// ## Dev vs prod backend
///
/// По умолчанию [baseUrl] = [vpsBaseUrl] (prod smoke на Pixel).
/// Для эмулятора: `flutter run --dart-define=APP_ENV=dev`
///
/// ## Платформенные URL (dev)
///
/// - Android emulator: [androidBaseUrl] (`http://10.0.2.2:8000/v2` when useV2)
/// - Физический Android: `adb reverse tcp:8000 tcp:8000` + `http://127.0.0.1:8000`
/// - iOS simulator: [iosBaseUrl]
/// - Desktop: [desktopBaseUrl]
class AppConfig {
  AppConfig._();

  /// Prefer Ogon-parity `/v2` control plane (ADR 009). Legacy `/api/v1` fallback
  /// via [useV2Api]=false for one release if needed.
  static const bool useV2Api = bool.fromEnvironment(
    'USE_V2_API',
    defaultValue: true,
  );

  /// Production API origin (scheme + host + port), no path.
  static const String vpsApiOrigin = 'https://api.teremokconnect.online:8443';

  /// Production backend — `/v2` (ADR 009) or legacy `/api/v1`.
  static const String vpsBaseUrl =
      useV2Api ? '$vpsApiOrigin/v2' : '$vpsApiOrigin/api/v1';

  /// Seed hosts for discovery failover (own domains only — not Огонь .xyz).
  static const List<String> discoverySeedHosts = [
    'https://api.teremokconnect.online:8443',
    'https://api2.teremokconnect.online:8443',
  ];

  /// Hostname for the RF control-plane API (no scheme / path).
  static const String vpsHostname = 'api.teremokconnect.online';

  /// Compile-time override for the control-plane A-record used by TUN
  /// `excludeRoute` and Xray DNS `hosts` pin. Empty → [vpsIpv4Fallback].
  ///
  /// Override: `--dart-define=VPS_CONTROL_PLANE_IPV4=1.2.3.4`
  static const String _vpsControlPlaneIpv4Override = String.fromEnvironment(
    'VPS_CONTROL_PLANE_IPV4',
    defaultValue: '',
  );

  /// Last-known good A-record for [vpsHostname] (RF). Prefer override / DNS
  /// resolution at runtime where available; this is the offline fallback so
  /// TUN bypass and Xray hosts pin stay valid if the A-record moves.
  static const String vpsIpv4Fallback = '130.49.149.182';

  /// Effective control-plane IPv4 for routing / DNS hosts pin.
  static String get vpsControlPlaneIpv4 {
    final override = _vpsControlPlaneIpv4Override.trim();
    if (override.isNotEmpty) return override;
    return vpsIpv4Fallback;
  }

  /// Alias kept for existing call sites (TUN exclude, Dio happy-eyeballs).
  static String get vpsIpv4 => vpsControlPlaneIpv4;

  /// Базовый URL API — dev defaults.
  static const String androidBaseUrl =
      useV2Api ? 'http://10.0.2.2:8000/v2' : 'http://10.0.2.2:8000/api/v1';
  static const String iosBaseUrl =
      useV2Api ? 'http://127.0.0.1:8000/v2' : 'http://127.0.0.1:8000/api/v1';
  static const String desktopBaseUrl =
      useV2Api ? 'http://localhost:8000/v2' : 'http://localhost:8000/api/v1';

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

  /// Build Dio baseUrl for [origin] honouring [useV2Api].
  static String baseUrlForOrigin(String origin) {
    final o = origin.trim().replaceAll(RegExp(r'/+$'), '');
    return useV2Api ? '$o/v2' : '$o/api/v1';
  }

  /// Таймаут dio по умолчанию.
  /// Flash-call ждёт ответ Zvonok на backend — даём запас на мобильной сети.
  static const Duration connectTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 60);

  /// Длиннее для /auth/flash-call/* (Zvonok API на backend может отвечать 15–30 с).
  static const Duration authConnectTimeout = Duration(seconds: 45);
  static const Duration authReceiveTimeout = Duration(seconds: 90);

  /// Anonymous UUID cold start (no Flash Call). Pair with backend
  /// `FEATURE_AUTH_ANONYMOUS=true`. Override: `--dart-define=AUTH_ANONYMOUS=false`
  /// for legacy phone alpha builds.
  static const bool authAnonymous = bool.fromEnvironment(
    'AUTH_ANONYMOUS',
    defaultValue: true,
  );

  /// Owner support Telegram username (no @). Prefill via [SupportContact].
  static const String supportTelegramUsername = 'deathnkomatoz';

  /// Bare chat link (no prefill). Prefer [SupportContact.open].
  static const String supportTelegramUrl =
      'https://t.me/$supportTelegramUsername';
}
