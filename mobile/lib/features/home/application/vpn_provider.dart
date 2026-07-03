import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_provider.dart';
import '../../auth/application/auth_state.dart';
import '../../vpn/data/vpn_config.dart';
import '../../vpn/data/vpn_config_repository.dart';
import 'vpn_status.dart';

/// Singleton-репозиторий для VPN-конфига.
final vpnConfigRepositoryProvider = Provider<VpnConfigRepository>(
  (ref) => VpnConfigRepository(),
);

/// VPN-контроллер. Шаг 10: использует [VpnConfigRepository] для получения
/// конфига перед "подключением". Реальный sing-box стартанёт в Шаге 14.
class VpnNotifier extends Notifier<VpnStatus> {
  VpnConfig? _config;

  /// Последний полученный конфиг. Доступен из UI для preview.
  VpnConfig? get config => _config;

  @override
  VpnStatus build() {
    // Если пользователь разлогинился — сбрасываем VPN в Disconnected
    // и чистим кеш репозитория.
    ref.listen<AsyncValue<AuthState>>(authProvider, (prev, next) {
      if (next.valueOrNull is! AuthStateAuthenticated) {
        if (state is! VpnDisconnected) {
          state = const VpnDisconnected();
        }
        _config = null;
        ref.read(vpnConfigRepositoryProvider).clearCache();
      }
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
      // 1. Получаем конфиг
      _config = await ref.read(vpnConfigRepositoryProvider).getConfig();
      state = const VpnConnecting(progress: 0.3);

      // 2. Mock: имитируем поэтапное подключение
      await _mockConnectProgress();

      // 3. Финал — Connected (но не реальный VPN до Шага 14)
      final serverName = _config?.username ?? 'unknown';
      final protocol =
          _config?.singBoxConfig.primaryOutbound?.type ?? 'unknown';
      state = VpnConnected(
        serverName: serverName,
        protocol: protocol,
        connectedSince: DateTime.now(),
      );
    } catch (e) {
      state = VpnError(message: 'Не удалось получить конфиг: $e');
    }
  }

  Future<void> disconnect() async {
    if (state is! VpnConnected) return;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    state = const VpnDisconnected();
  }

  Future<void> _mockConnectProgress() async {
    for (final p in const [0.5, 0.7, 0.9, 1.0]) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (state is VpnConnecting) {
        state = VpnConnecting(progress: p);
      }
    }
  }
}

final vpnProvider = NotifierProvider<VpnNotifier, VpnStatus>(
  VpnNotifier.new,
);