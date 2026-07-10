import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/token_storage.dart';
import 'auth_state.dart';

/// AsyncNotifier<AuthState>: при первом обращении проверяет secure storage.
///
/// Не дёргает сеть — только локальное хранилище. Сетевая проверка токенов
/// будет в Шаге 19 (GET /v1/users/me).
class AuthNotifier extends AsyncNotifier<AuthState> {
  @override
  Future<AuthState> build() async {
    try {
      final tokens = TokenStorage.instance;
      final access = await tokens.readAccessToken();
      final refresh = await tokens.readRefreshToken();
      if (access != null &&
          refresh != null &&
          access.isNotEmpty &&
          refresh.isNotEmpty) {
        return AuthStateAuthenticated(
          accessToken: access,
          refreshToken: refresh,
        );
      }
    } catch (e, st) {
      debugPrint('auth.restore_failed: $e\n$st');
    }
    return const AuthStateUnauthenticated();
  }

  /// После успешного POST /auth/flash-call/verify.
  Future<void> authenticated({
    required String accessToken,
    required String refreshToken,
  }) async {
    await TokenStorage.instance.saveTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
    state = AsyncData(
      AuthStateAuthenticated(
        accessToken: accessToken,
        refreshToken: refreshToken,
      ),
    );
  }

  /// После logout или неуспешной ротации refresh-токена.
  Future<void> unauthenticated() async {
    await TokenStorage.instance.clear();
    state = const AsyncData(AuthStateUnauthenticated());
  }

  /// После фонового refresh через JwtRefreshInterceptor.
  Future<void> tokensRotated({
    required String accessToken,
    required String refreshToken,
  }) async {
    state = AsyncData(
      AuthStateAuthenticated(
        accessToken: accessToken,
        refreshToken: refreshToken,
      ),
    );
  }
}

final authProvider = AsyncNotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);

/// `Listenable`-адаптер для GoRouter: дёргает `notifyListeners()` при смене auth.
///
/// Подписывается на [authProvider] в main.dart через [ProviderContainer.listen]
/// и уведомляет GoRouter, чтобы тот пересчитал `redirect`.
class GoRouterRefreshNotifier extends ChangeNotifier {
  void notifyAuthChanged() => notifyListeners();
}