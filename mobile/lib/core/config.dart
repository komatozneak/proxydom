/// Конфигурация приложения.
///
/// baseUrl по умолчанию указывает на Android-эмулятор (10.0.2.2 — это
/// localhost на хост-машине с точки зрения эмулятора).
/// Для физического Android через USB используй `adb reverse tcp:8000 tcp:8000`
/// и переключи [androidBaseUrl] на http://localhost:8000
/// Для iOS-симулятора — http://127.0.0.1:8000
/// Для Windows/macOS/Linux desktop — http://localhost:8000
class AppConfig {
  AppConfig._();

  /// Базовый URL API (с /api/v1 на конце).
  static const String androidBaseUrl = 'http://10.0.2.2:8000/api/v1';
  static const String iosBaseUrl = 'http://127.0.0.1:8000/api/v1';
  static const String desktopBaseUrl = 'http://localhost:8000/api/v1';

  /// Активный base URL выбирается на старте приложения платформо-зависимо.
  /// Прямо здесь выставляем Android-значение как дефолт; в lib/main.dart
  /// потом (Шаг 4a, если нужно) переключим по Platform.isXxx.
  static const String baseUrl = androidBaseUrl;

  /// Таймаут dio по умолчанию.
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 15);
}
