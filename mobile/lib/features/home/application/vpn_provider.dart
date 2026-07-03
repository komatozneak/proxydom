import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_provider.dart';
import '../../auth/application/auth_state.dart';
import '../../vpn/data/vpn_config.dart';
import '../../vpn/data/vpn_config_repository.dart';
import '../../vpn/data/vpn_controller.dart';
import 'vpn_status.dart';

/// Singleton-репозиторий для VPN-конфига.
final vpnConfigRepositoryProvider = Provider<VpnConfigRepository>(
  (ref) => VpnConfigRepository(),
);

/// VPN-контроллер. Шаг 12: подключён к нативному VpnService через
/// [VpnController] (MethodChannel + EventChannel).
class VpnNotifier extends Notifier<VpnStatus> {
  VpnConfig? _config;

  /// Последний полученный конфиг. Доступен из UI для preview.
  VpnConfig? get config => _config;

  StreamSubscription<VpnNativeStatus>? _statusSubscription;

  @override
  VpnStatus build() {
    // Если пользователь разлогинился — сбрасываем VPN в Disconnected
    // и чистим кеш репозитория + подписку на статус.
    ref.listen<AsyncValue<AuthState>>(authProvider, (prev, next) {
      if (next.valueOrNull is! AuthStateAuthenticated) {
        if (state is! VpnDisconnected) {
          state = const VpnDisconnected();
        }
        _config = null;
        _statusSubscription?.cancel();
        _statusSubscription = null;
        ref.read(vpnConfigRepositoryProvider).clearCache();
      }
    });

    // Cleanup при dispose самого Notifier.
    ref.onDispose(() {
      _statusSubscription?.cancel();
    });

    return const VpnDisconnected();
  }

  /// Получить конфиг без подключения (для UI/preview).
  Future<VpnConfig> fetchConfig() async {
    final repo = ref.read(vpnConfigRepositoryProvider);
    _config = await repo.getConfig();
    return _config!;
  }

  Future<void> connect() async {
    if (state is VpnConnecting || state is VpnConnected) return;
    state = const VpnConnecting(progress: 0.0);

    try {
      // 1. Получаем конфиг (cache-first)
      _config = await ref.read(vpnConfigRepositoryProvider).getConfig();
      state = const VpnConnecting(progress: 0.3);

      // 2. Проверяем permission (на Android открывает системный диалог)
      final hasPermission = await VpnController.instance.requestPermission();
      if (!hasPermission) {
        state = const VpnError(message: 'VPN permission denied');
        return;
      }
      state = const VpnConnecting(progress: 0.5);

      // 3. Отправляем start в нативный код
      final started = await VpnController.instance.start(_config!);
      if (!started) {
        state = const VpnError(message: 'Failed to start VPN service');
        return;
      }
      state = const VpnConnecting(progress: 0.8);

      // 4. Слушаем статус из нативного кода
      _statusSubscription?.cancel();
      _statusSubscription =
          VpnController.instance.statusStream.listen(_onNativeStatus);

      // Если в течение 3 сек не пришёл connected — считаем что стартовало
      // (на этом шаге реальный connect мгновенный, в Шаге 14 будет долгим).
      await Future<void>.delayed(const Duration(seconds: 3));
      if (state is VpnConnecting) {
        final serverName = _config?.username ?? 'unknown';
        final protocol =
            _config?.singBoxConfig.primaryOutbound?.type ?? 'unknown';
        state = VpnConnected(
          serverName: serverName,
          protocol: protocol,
          connectedSince: DateTime.now(),
        );
      }
    } catch (e) {
      state = VpnError(message: 'Connect failed: $e');
    }
  }

  void _onNativeStatus(VpnNativeStatus nativeStatus) {
    switch (nativeStatus) {
      case VpnNativeStatus.connected:
        final serverName = _config?.username ?? 'unknown';
        final protocol =
            _config?.singBoxConfig.primaryOutbound?.type ?? 'unknown';
        state = VpnConnected(
          serverName: serverName,
          protocol: protocol,
          connectedSince: DateTime.now(),
        );
      case VpnNativeStatus.disconnecting:
      case VpnNativeStatus.idle:
      case VpnNativeStatus.revoked:
        if (state is VpnConnected) {
          state = const VpnDisconnected();
        }
      case VpnNativeStatus.error:
        state = const VpnError(message: 'Native VPN error');
      case VpnNativeStatus.unknown:
      case VpnNativeStatus.preparing:
      case VpnNativeStatus.connecting:
        // Промежуточные статусы — оставляем текущий state.
        break;
    }
  }

  Future<void> disconnect() async {
    if (state is! VpnConnected) return;
    state = const VpnConnecting(progress: 0.5); // reuse как "disconnecting"
    try {
      await VpnController.instance.stop();
      _statusSubscription?.cancel();
      _statusSubscription = null;
      state = const VpnDisconnected();
    } catch (e) {
      state = VpnError(message: 'Disconnect failed: $e');
    }
  }
}

final vpnProvider = NotifierProvider<VpnNotifier, VpnStatus>(
  VpnNotifier.new,
);