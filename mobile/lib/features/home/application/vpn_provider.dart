import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_provider.dart';
import '../../auth/application/auth_state.dart';
import 'vpn_status.dart';

/// VPN-контроллер (mock до Шага 14, где подключим sing-box).
class VpnNotifier extends Notifier<VpnStatus> {
  @override
  VpnStatus build() {
    // Если пользователь разлогинился — сбрасываем VPN в Disconnected.
    ref.listen<AsyncValue<AuthState>>(authProvider, (prev, next) {
      if (next.valueOrNull is! AuthStateAuthenticated) {
        if (state is! VpnDisconnected) {
          state = const VpnDisconnected();
        }
      }
    });
    return const VpnDisconnected();
  }

  Future<void> connect() async {
    if (state is VpnConnecting || state is VpnConnected) return;
    state = const VpnConnecting(progress: 0.0);
    await _mockConnectProgress();
    state = VpnConnected(
      serverName: 'Germany #1',
      protocol: 'VLESS+Reality',
      connectedSince: DateTime.now(),
    );
  }

  Future<void> disconnect() async {
    if (state is! VpnConnected) return;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (ref is! ProviderSubscription) {
      // notifier отключён — выходим без обновления state
      return;
    }
    state = const VpnDisconnected();
  }

  Future<void> _mockConnectProgress() async {
    for (final p in const [0.3, 0.6, 0.85, 1.0]) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (state is! VpnConnecting) return;
      state = VpnConnecting(progress: p);
    }
  }
}

final vpnProvider = NotifierProvider<VpnNotifier, VpnStatus>(
  VpnNotifier.new,
);