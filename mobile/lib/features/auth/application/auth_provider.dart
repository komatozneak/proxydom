import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_secret_storage.dart';
import '../../../core/config.dart';
import '../../../core/install_id_storage.dart';
import '../../../core/router.dart';
import '../../../core/token_storage.dart';
import '../data/auth_api.dart';
import '../data/recovery_code_storage.dart';
import '../data/seat_invite_local_store.dart';
import '../data/seat_outcome.dart';
import 'auth_state.dart';

export '../data/seat_outcome.dart';

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
        final secret = (await ApiSecretStorage.instance.read())?.trim();
        if (secret != null && secret.isNotEmpty) {
          return AuthStateAuthenticated(
            accessToken: access,
            refreshToken: refresh,
          );
        }
        // ADR 012: JWT without api_secret → unsigned /v2. Re-register same
        // install id so server re-returns the existing plaintext secret.
        debugPrint('auth.restore_missing_api_secret → re-register');
        return _registerDevice();
      }
    } catch (e, st) {
      debugPrint('auth.restore_failed: $e\n$st');
    }

    if (AppConfig.authAnonymous) {
      return _registerDevice();
    }

    return const AuthStateUnauthenticated();
  }

  Future<AuthState> _registerDevice({bool allowInstallRotate = true}) async {
    try {
      final result = await AuthApi().register(platform: 'android').timeout(
            const Duration(seconds: 45),
          );
      await TokenStorage.instance.saveTokens(
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
      );
      await result.persistApiSecret();
      final secret = result.apiSecret?.trim();
      if (secret == null || secret.isEmpty) {
        // Should not happen after server re-returns existing secret; last resort.
        if (allowInstallRotate) {
          debugPrint('auth.register_empty_api_secret → rotate install + retry');
          await ApiSecretStorage.instance.clear();
          await InstallIdStorage.instance.rotate();
          return _registerDevice(allowInstallRotate: false);
        }
        debugPrint('auth.register_empty_api_secret → bootstrap failed');
        return const AuthStateBootstrapFailed();
      }
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
      final secret = result.apiSecret?.trim();
      if (secret == null || secret.isEmpty) {
        debugPrint('auth.recover_empty_api_secret');
        return false;
      }
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

  Future<SeatMakeOutcome> makeSeatCode() async {
    try {
      final result = await AuthApi().makeSeatCode();
      final code = result.code.trim();
      if (code.isEmpty) return const SeatMakeFailed();
      await SeatInviteLocalStore.instance.rememberMinted(code);
      return SeatMakeOk(code);
    } on SeatApiException catch (e, st) {
      debugPrint('auth.seat_make_failed: $e\n$st');
      if (detailLooksLikePremiumRequired(e.detail, errorCode: e.errorCode)) {
        return const SeatMakePremiumRequired();
      }
      return const SeatMakeFailed();
    } catch (e, st) {
      debugPrint('auth.seat_make_failed: $e\n$st');
      return const SeatMakeFailed();
    }
  }

  Future<SeatAcceptOutcome> acceptSeatCode(String code) async {
    // Local guard: works even if prod API is older than own_seat_code.
    if (await SeatInviteLocalStore.instance.wasMintedHere(code)) {
      debugPrint('auth.seat_accept_blocked: own code minted on this install');
      return SeatAcceptOutcome.ownCode;
    }
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
      return SeatAcceptOutcome.ok;
    } on SeatApiException catch (e, st) {
      debugPrint('auth.seat_accept_failed: $e\n$st');
      if (e.statusCode == 404) return SeatAcceptOutcome.notFound;
      if (detailLooksLikePremiumRequired(e.detail, errorCode: e.errorCode)) {
        return SeatAcceptOutcome.premiumRequired;
      }
      if (e.statusCode == 403 || detailLooksLikeDeviceLimit(e.detail)) {
        return SeatAcceptOutcome.limit;
      }
      if (e.statusCode == 400 &&
          detailLooksLikeOwnSeatCode(e.detail, errorCode: e.errorCode)) {
        return SeatAcceptOutcome.ownCode;
      }
      // Older API may return plain 400 string — still treat as own when clear.
      if (e.statusCode == 400 && detailLooksLikeOwnSeatCode(e.detail)) {
        return SeatAcceptOutcome.ownCode;
      }
      return SeatAcceptOutcome.failed;
    } catch (e, st) {
      debugPrint('auth.seat_accept_failed: $e\n$st');
      return SeatAcceptOutcome.failed;
    }
  }
}

final authProvider = AsyncNotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);

class GoRouterRefreshNotifier extends ChangeNotifier {
  void notifyAuthChanged() => notifyListeners();
}
