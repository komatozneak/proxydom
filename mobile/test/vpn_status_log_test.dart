import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/features/home/application/vpn_status.dart';
import 'package:proxydom/features/home/application/vpn_status_log.dart';
import 'package:proxydom/features/vpn/data/vpn_controller.dart';

void main() {
  test('repeated native status does not emit another line', () {
    final log = NativeStatusLog();
    expect(log.lineFor(VpnNativeStatus.idle), 'vpn.native status=idle');
    expect(log.lineFor(VpnNativeStatus.idle), isNull);
    expect(log.lineFor(VpnNativeStatus.connected), 'vpn.native status=connected');
    expect(log.lineFor(VpnNativeStatus.connected), isNull);
  });

  test('ui phase is a name, not the Dart instance', () {
    expect(vpnUiPhase(const VpnDisconnected()), 'disconnected');
    expect(vpnUiPhase(const VpnConnecting(progress: 0.5)), 'connecting');
  });

  test('a live free session is not opened again', () {
    expect(
      keepLiveFreeSession(
        freeClient: true,
        sessionOpen: true,
        sameProfile: true,
      ),
      isTrue,
    );
    expect(
      keepLiveFreeSession(
        freeClient: true,
        sessionOpen: true,
        sameProfile: false,
      ),
      isFalse,
    );
    expect(
      keepLiveFreeSession(
        freeClient: false,
        sessionOpen: true,
        sameProfile: true,
      ),
      isFalse,
    );
  });

  test('profile host is logged without the share secret', () {
    expect(profileHostForLog('85.155.228.235:443'), '85.155.228.235');
    expect(profileHostForLog('node.example:443'), 'node.example');
  });
}
