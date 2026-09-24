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

/// Host from `host:port`. The share URI itself is never logged.
String? profileHostForLog(String endpoint) {
  final host = Uri.tryParse('x://$endpoint')?.host;
  if (host == null || host.isEmpty) return null;
  return host;
}

/// Free-client tunnel already up for this profile. A later snapshot must not
/// open a second session or close the clock.
bool keepLiveFreeSession({
  required bool freeClient,
  required bool sessionOpen,
  required bool sameProfile,
}) =>
    freeClient && sessionOpen && sameProfile;
