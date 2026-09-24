import '../../vpn/data/vpn_controller.dart';
import 'vpn_status.dart';

/// One line per native status change. Repeated polls of the same status
/// are not events.
class NativeStatusLog {
  VpnNativeStatus? _last;

  String? lineFor(VpnNativeStatus status) {
    if (_last == status) return null;
    _last = status;
    return 'vpn.native status=${status.name}';
  }
}

String vpnUiPhase(VpnStatus state) => switch (state) {
      VpnDisconnected() => 'disconnected',
      VpnConnecting() => 'connecting',
      VpnConnected() => 'connected',
      VpnError() => 'error',
    };
