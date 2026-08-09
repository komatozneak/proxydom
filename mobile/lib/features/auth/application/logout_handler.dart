import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_secret_storage.dart';
import '../../../core/config.dart';
import '../../../core/router.dart';
import '../../../core/token_storage.dart';
import '../../home/application/vpn_provider.dart';
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

  Future<LogoutResult> logout() async {
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

      AppRouter.postAuthResolved = false;
      try {
        await _ref.read(authProvider.notifier).unauthenticated();
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
    await vpnNotifier.disconnect();
  }
}

final logoutHandlerProvider = Provider<LogoutHandler>((ref) {
  return LogoutHandler(ref);
});
