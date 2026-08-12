/// Состояние авторизации — sealed-иерархия для compile-time exhaustive switch.
///
/// Используется в [AuthNotifier] (см. auth_provider.dart) и читается
/// виджетами через `ref.watch(authProvider)`.
sealed class AuthState {
  const AuthState();
}

/// Стартовое состояние — пока не знаем, авторизован ли пользователь
/// (например, во время первой проверки secure storage).
final class AuthStateUnknown extends AuthState {
  const AuthStateUnknown();
}

/// Юзер залогинен. Токены лежат в secure storage и здесь — для UI/redirect.
final class AuthStateAuthenticated extends AuthState {
  const AuthStateAuthenticated({
    required this.accessToken,
    required this.refreshToken,
  });

  final String accessToken;
  final String refreshToken;
}

/// Юзер не залогинен (или только что разлогинился).
final class AuthStateUnauthenticated extends AuthState {
  const AuthStateUnauthenticated();
}

/// Anonymous bootstrap failed (AUTH_ANONYMOUS) — show retry UI.
final class AuthStateBootstrapFailed extends AuthState {
  const AuthStateBootstrapFailed();
}