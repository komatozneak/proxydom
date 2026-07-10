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

  /// Production backend на Yottasrc VPS (ADR-001 gate smoke).
  static const String vpsBaseUrl = 'http://204.11.2.216:8080/api/v1';

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
}
