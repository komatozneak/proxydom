/// Конфигурация приложения.
///
/// ## Dev vs prod backend
///
/// По умолчанию [baseUrl] = [vpsBaseUrl] (prod smoke на Pixel).
/// Для эмулятора: `flutter run --dart-define=APP_ENV=dev`
///
/// ## Платформенные URL (dev)
///
/// - Android emulator: [androidBaseUrl] (`http://10.0.2.2:8000/api/v1`)
/// - Физический Android: `adb reverse tcp:8000 tcp:8000` + `http://127.0.0.1:8000`
/// - iOS simulator: [iosBaseUrl]
/// - Desktop: [desktopBaseUrl]
class AppConfig {
  AppConfig._();

  /// Production backend — HTTPS via Caddy :8443 (Reality keeps :443).
  ///
  /// No trailing slash. Dio joins `baseUrl + path`, so API paths must start
  /// with `/` (e.g. `/vpn/nodes`, `/billing/subscription`) or the `v1` segment
  /// concatenates into the next path segment (`/api/v1billing/...`).
  static const String vpsBaseUrl =
      'https://api.teremokconnect.online:8443/api/v1';

  /// A-record for [vpsBaseUrl] host (RF control-plane) — TUN exclude / sing-box
  /// direct CIDR (hostname/32 is invalid). Reality egress stays on DE nodes.
  static const String vpsIpv4 = '130.49.149.182';

  /// Базовый URL API (с /api/v1 на конце) — dev defaults.
  static const String androidBaseUrl = 'http://10.0.2.2:8000/api/v1';
  static const String iosBaseUrl = 'http://127.0.0.1:8000/api/v1';
  static const String desktopBaseUrl = 'http://localhost:8000/api/v1';

  /// Compile-time env: `prod` (default на физ. устройстве) или `dev` (эмулятор).
  /// Эмулятор: `flutter run --dart-define=APP_ENV=dev`
  static const String _appEnv = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'prod',
  );

  /// Активный base URL. Dev по умолчанию — не менять на [vpsBaseUrl] напрямую.
  static const String baseUrl =
      _appEnv == 'prod' ? vpsBaseUrl : androidBaseUrl;

  /// Resolve base URL for a given env label (used in tests).
  static String baseUrlForEnvironment(String appEnv) =>
      appEnv == 'prod' ? vpsBaseUrl : androidBaseUrl;

  /// Таймаут dio по умолчанию.
  /// Flash-call ждёт ответ Zvonok на VPS — даём запас на мобильной сети.
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
