import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config.dart';
import '../../../core/token_storage.dart';
import '../data/auth_api.dart';
import 'auth_state.dart';

/// AsyncNotifier<AuthState>: secure storage restore + optional anonymous bootstrap.
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

    if (AppConfig.authAnonymous) {
      return _bootstrapAnonymous();
    }

    return const AuthStateUnauthenticated();
  }

  Future<AuthState> _bootstrapAnonymous() async {
    try {
      final result = await AuthApi().bootstrap().timeout(
            const Duration(seconds: 45),
          );
      await TokenStorage.instance.saveTokens(
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
      );
      return AuthStateAuthenticated(
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
      );
    } catch (e, st) {
      debugPrint('auth.bootstrap_failed: $e\n$st');
      return const AuthStateBootstrapFailed();
    }
  }

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

  /// After logout / failed refresh.
  ///
  /// Anonymous: re-bootstrap **without** [AsyncLoading] (that froze Settings
  /// logout spinner and raced JWT SessionExpired → logout loop).
  Future<void> unauthenticated() async {
    await TokenStorage.instance.clear();
    if (AppConfig.authAnonymous) {
      state = AsyncData(await _bootstrapAnonymous());
      return;
    }
    state = const AsyncData(AuthStateUnauthenticated());
  }

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

  /// Retry anonymous bootstrap after network failure (BootstrapFailedScreen).
  Future<void> retryBootstrap() async {
    state = const AsyncLoading();
    state = AsyncData(await _bootstrapAnonymous());
  }
}

final authProvider = AsyncNotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);

class GoRouterRefreshNotifier extends ChangeNotifier {
  void notifyAuthChanged() => notifyListeners();
}
