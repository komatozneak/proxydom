import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config.dart';
import '../../../core/router.dart';
import '../../../core/token_storage.dart';
import '../data/auth_api.dart';
import '../data/recovery_code_storage.dart';
import 'auth_state.dart';

/// AsyncNotifier<AuthState>: secure storage restore + device register.
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
      return _registerDevice();
    }

    return const AuthStateUnauthenticated();
  }

  Future<AuthState> _registerDevice() async {
    try {
      final result = await AuthApi().register(platform: 'android').timeout(
            const Duration(seconds: 45),
          );
      await TokenStorage.instance.saveTokens(
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
      );
      await result.persistApiSecret();
      final code = result.recoveryCode?.trim();
      if (code != null && code.isNotEmpty) {
        await RecoveryCodeStorage.instance.savePending(code);
        AppRouter.pendingRecoveryCode = code;
      }
      return AuthStateAuthenticated(
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
      );
    } catch (e, st) {
      debugPrint('auth.register_failed: $e\n$st');
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
  Future<void> unauthenticated() async {
    await TokenStorage.instance.clear();
    if (AppConfig.authAnonymous) {
      state = AsyncData(await _registerDevice());
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

  /// Retry device register after network failure.
  Future<void> retryBootstrap() async {
    state = const AsyncLoading();
    state = AsyncData(await _registerDevice());
  }

  /// Reinstall recovery: bind new install to account via recovery code.
  Future<bool> recoverWithCode(String recoveryCode) async {
    try {
      final result = await AuthApi().recover(recoveryCode: recoveryCode).timeout(
            const Duration(seconds: 45),
          );
      await TokenStorage.instance.saveTokens(
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
      );
      await result.persistApiSecret();
      state = AsyncData(
        AuthStateAuthenticated(
          accessToken: result.accessToken,
          refreshToken: result.refreshToken,
        ),
      );
      return true;
    } catch (e, st) {
      debugPrint('auth.recover_failed: $e\n$st');
      return false;
    }
  }

  Future<String?> makeSeatCode() async {
    try {
      final result = await AuthApi().makeSeatCode();
      return result.code;
    } catch (e, st) {
      debugPrint('auth.seat_make_failed: $e\n$st');
      return null;
    }
  }

  Future<bool> acceptSeatCode(String code) async {
    try {
      final result = await AuthApi().acceptSeatCode(code: code);
      await TokenStorage.instance.saveTokens(
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
      );
      await result.persistApiSecret();
      state = AsyncData(
        AuthStateAuthenticated(
          accessToken: result.accessToken,
          refreshToken: result.refreshToken,
        ),
      );
      return true;
    } catch (e, st) {
      debugPrint('auth.seat_accept_failed: $e\n$st');
      return false;
    }
  }
}

final authProvider = AsyncNotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);

class GoRouterRefreshNotifier extends ChangeNotifier {
  void notifyAuthChanged() => notifyListeners();
}
