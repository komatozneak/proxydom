/// Политика повторных попыток с exponential backoff.
///
/// Используется для HTTP запросов и MethodChannel вызовов в VPN-слое.
class RetryPolicy {
  RetryPolicy({
    this.maxAttempts = 3,
    this.initialDelay = const Duration(milliseconds: 500),
    this.maxDelay = const Duration(seconds: 5),
    this.backoffMultiplier = 2.0,
  });

  /// Максимальное количество попыток (включая первую).
  final int maxAttempts;

  /// Задержка перед 2-й попыткой.
  final Duration initialDelay;

  /// Максимальная задержка (cap для exponential growth).
  final Duration maxDelay;

  /// Множитель backoff (2.0 = удвоение).
  final double backoffMultiplier;

  /// Вычислить задержку для [attempt] (1-based).
  ///
  /// attempt=1 → Duration.zero (первая попытка без задержки).
  /// attempt=2 → initialDelay.
  /// attempt=3 → initialDelay * backoffMultiplier.
  /// и т.д., capped в maxDelay.
  Duration delayFor(int attempt) {
    if (attempt <= 1) return Duration.zero;
    final ms = initialDelay.inMilliseconds *
        (backoffMultiplier * (attempt - 1)).toInt();
    final cappedMs = ms.clamp(0, maxDelay.inMilliseconds);
    return Duration(milliseconds: cappedMs);
  }

  /// Выполнить [action] с retry.
  ///
  /// [shouldRetry] — предикат: повторять ли на этом исключении
  /// (например, для DioException можно проверить type).
  ///
  /// [onRetry] — коллбэк после каждой неудачной попытки (для логирования).
  Future<T> execute<T>(
    Future<T> Function() action, {
    Future<bool> Function(Object error)? shouldRetry,
    void Function(int attempt, Object error)? onRetry,
  }) async {
    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await action();
      } catch (e) {
        lastError = e;
        if (attempt == maxAttempts) break;
        final retry = shouldRetry == null ? true : await shouldRetry(e);
        if (!retry) break;
        final delay = delayFor(attempt);
        onRetry?.call(attempt, e);
        await Future<void>.delayed(delay);
      }
    }
    throw lastError!;
  }
}