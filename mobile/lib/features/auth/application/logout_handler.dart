import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

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
///
/// Вызывается:
/// - Из HomeScreen при нажатии Logout (с подтверждением через AlertDialog)
/// - Из authProvider при forced logout (refresh fail, 401 chain — Шаг 19)
/// - При истечении refresh token (после Шага 19)
class LogoutHandler {
  LogoutHandler(this._ref);

  final Ref _ref;

  /// Выполнить logout с гарантированной очисткой всех слоёв.
  ///
  /// Шаги (в строгом порядке):
  /// 1. Остановить VPN (через VpnNotifier.disconnect() — внутри timeout)
  /// 2. Очистить VPN cache
  /// 3. Очистить secure storage (токены)
  /// 4. Сбросить authProvider в Unauthenticated
  ///    → VpnNotifier._cleanupOnLogout() сработает через ref.listen
  ///    → GoRouter.redirect автоматически перенаправит на /login
  ///
  /// Если любой шаг падает — продолжаем (best-effort), но возвращаем
  /// [LogoutPartialFailure] с сообщением для UI.
  Future<LogoutResult> logout() async {
    final errors = <String>[];

    // 1. Остановить VPN
    try {
      await _stopVpnWithTimeout();
    } catch (e) {
      errors.add('VPN stop: $e');
    }

    // 2. Очистить VPN cache
    try {
      _ref.read(vpnConfigRepositoryProvider).clearCache();
    } catch (e) {
      errors.add('VPN cache: $e');
    }

    // 3. Очистить secure storage
    try {
      await TokenStorage.instance.clear();
    } catch (e) {
      errors.add('TokenStorage.clear: $e');
    }

    // 4. Сбросить authProvider — это запустит cleanupOnLogout в VpnNotifier
    //    и через refreshListenable → GoRouter.redirect уйдёт с /home на /login.
    try {
      // Drop gate/shell latch so next login cannot skip promo.
      AppRouter.postAuthResolved = false;
      await _ref.read(authProvider.notifier).unauthenticated();
    } catch (e) {
      errors.add('authProvider: $e');
    }

    if (errors.isEmpty) {
      return const LogoutSuccess();
    } else {
      return LogoutPartialFailure(errors.join('; '));
    }
  }

  Future<void> _stopVpnWithTimeout() async {
    final vpnNotifier = _ref.read(vpnProvider.notifier);
    await vpnNotifier.disconnect();
  }
}

/// Provider для LogoutHandler (singleton).
final logoutHandlerProvider = Provider<LogoutHandler>((ref) {
  return LogoutHandler(ref);
});