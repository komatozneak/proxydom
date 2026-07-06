/// Конфигурация приложения.
///
/// ## Dev vs prod backend
///
/// По умолчанию [baseUrl] указывает на Android-эмулятор (`10.0.2.2` = localhost
/// хост-машины). Для **production smoke** на Yottasrc VPS:
///
/// ```bash
/// flutter run --dart-define=APP_ENV=prod
/// ```
///
/// Это переключит [baseUrl] на [vpsBaseUrl] (`204.11.2.216:8080`).
///
/// ## Платформенные URL (dev)
///
/// - Android emulator: [androidBaseUrl] (`http://10.0.2.2:8000/api/v1`)
/// - Физический Android: `adb reverse tcp:8000 tcp:8000` + `http://127.0.0.1:8000`
/// - iOS simulator: [iosBaseUrl]
/// - Desktop: [desktopBaseUrl]
class AppConfig {
  AppConfig._();

  /// Production backend на Yottasrc VPS (ADR-001 gate smoke).
  static const String vpsBaseUrl = 'http://204.11.2.216:8080/api/v1';

  /// Базовый URL API (с /api/v1 на конце) — dev defaults.
  static const String androidBaseUrl = 'http://10.0.2.2:8000/api/v1';
  static const String iosBaseUrl = 'http://127.0.0.1:8000/api/v1';
  static const String desktopBaseUrl = 'http://localhost:8000/api/v1';

  /// Compile-time env: `dev` (default) или `prod` (`--dart-define=APP_ENV=prod`).
  static const String _appEnv = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'dev',
  );

  /// Активный base URL. Dev по умолчанию — не менять на [vpsBaseUrl] напрямую.
  static const String baseUrl =
      _appEnv == 'prod' ? vpsBaseUrl : androidBaseUrl;

  /// Resolve base URL for a given env label (used in tests).
  static String baseUrlForEnvironment(String appEnv) =>
      appEnv == 'prod' ? vpsBaseUrl : androidBaseUrl;

  /// Таймаут dio по умолчанию.
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 15);
}
