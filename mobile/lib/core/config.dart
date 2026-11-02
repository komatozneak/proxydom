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

  /// Production API. The hub serves `/api/v1`.
  static const String vpsBaseUrl = '$vpsApiOrigin/api/v1';

  /// Dev API base URL — Android emulator.
  static const String androidBaseUrl = 'http://10.0.2.2:8000/api/v1';
  static const String iosBaseUrl = 'http://127.0.0.1:8000/api/v1';
  static const String desktopBaseUrl = 'http://localhost:8000/api/v1';

  /// Compile-time env: `prod` (default on a physical device) or `dev`.
  /// Emulator: `flutter run --dart-define=APP_ENV=dev`
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

  /// Dio's default timeout.
  static const Duration connectTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 60);

  /// Bank / Play review — public legal pages (always-on footer).
  static const String privacyPolicyUrl = 'https://proxydom.su/privacy.html';

  static const String termsOfServiceUrl = 'https://proxydom.su/terms.html';

  static const String supportPageUrl = 'https://proxydom.su/support.html';

  /// Role contact shown in the app. Matches the site footer and the mailbox
  /// the Apple and D&B correspondence runs on.
  static const String supportEmail = 'support@proxydom.su';
}
