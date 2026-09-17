import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_secret_storage.dart';
import '../../../core/install_id_storage.dart';
import '../../../core/router.dart';
import '../../../core/token_storage.dart';
import '../../home/application/vpn_provider.dart';
import '../data/recovery_code_storage.dart';
import 'auth_provider.dart';

/// Результат logout операции.
sealed class LogoutResult {
  const LogoutResult();
}

class LogoutSuccess extends LogoutResult {
  const LogoutSuccess();
}

class LogoutPartialFailure extends LogoutResult {
  const LogoutPartialFailure(this.message);
  final String message;
}

/// Координатор logout — гарантирует полную очистку state.
class LogoutHandler {
  LogoutHandler(this._ref);

  final Ref _ref;

  /// Prevents SessionExpiredGate → logout → SessionExpired recursion.
  static bool inProgress = false;

  /// Full local wipe. [autoRegister] stays false: after logout / session
  /// expiry the user lands on Welcome (new account vs restore) instead of
  /// silently minting a fresh anonymous account and orphaning the old one.
  Future<LogoutResult> logout({bool autoRegister = false}) async {
    if (inProgress) {
      return const LogoutSuccess();
    }
    inProgress = true;
    final errors = <String>[];

    try {
      try {
        await _stopVpnWithTimeout();
      } catch (e) {
        errors.add('VPN stop: $e');
      }

      try {
        _ref.read(vpnConfigRepositoryProvider).clearCache();
      } catch (e) {
        errors.add('VPN cache: $e');
      }

      try {
        await TokenStorage.instance.clear();
      } catch (e) {
        errors.add('TokenStorage.clear: $e');
      }

      try {
        await ApiSecretStorage.instance.clear();
      } catch (e) {
        errors.add('ApiSecretStorage.clear: $e');
      }

      try {
        await RecoveryCodeStorage.instance.clear();
        AppRouter.pendingRecoveryCode = null;
      } catch (e) {
        errors.add('RecoveryCodeStorage.clear: $e');
      }

      // ADR 012: install dies whole — wipe id with secret so re-register mints anew.
      try {
        await InstallIdStorage.instance.rotate();
      } catch (e) {
        errors.add('InstallIdStorage.rotate: $e');
      }

      AppRouter.postAuthResolved = false;
      try {
        await _ref
            .read(authProvider.notifier)
            .unauthenticated(autoRegister: autoRegister);
      } catch (e) {
        errors.add('authProvider: $e');
      }
    } finally {
      inProgress = false;
    }

    if (errors.isEmpty) {
      return const LogoutSuccess();
    }
    return LogoutPartialFailure(errors.join('; '));
  }

  Future<void> _stopVpnWithTimeout() async {
    final vpnNotifier = _ref.read(vpnProvider.notifier);
    // One native call owns stop + persisted credential wipe.
    await vpnNotifier.disconnect(
      reason: 'logout',
      wipeNativeSession: true,
    );
  }
}

final logoutHandlerProvider = Provider<LogoutHandler>((ref) {
  return LogoutHandler(ref);
});
