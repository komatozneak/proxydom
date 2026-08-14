import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/features/vpn/data/vpn_session_snapshot.dart';
import 'package:teremok_connect/features/vpn/domain/vpn_connect_error.dart';

void main() {
  group('parseSocksProbeFailure', () {
    test('parses native failStart message', () {
      final parsed = parseSocksProbeFailure(
        'eu-primary@204.11.2.216: SOCKS HTTPS probe failed',
      );
      expect(parsed?.nodeId, 'eu-primary');
      expect(parsed?.host, '204.11.2.216');
    });

    test('returns null for unrelated errors', () {
      expect(parseSocksProbeFailure('Xray start failed'), isNull);
    });
  });

  group('vpnErrorFromNativeDetail', () {
    test('maps probe fail to server_probe_failed code', () {
      final err = vpnErrorFromNativeDetail(
        'eu-primary@204.11.2.216: SOCKS HTTPS probe failed',
      );
      expect(err.code, kVpnProbeFailedErrorCode);
      expect(err.message, 'eu-primary');
    });

    test('maps Auto prove miss to path_incompatible', () {
      final err = vpnErrorFromNativeDetail(
        'path_incompatible: auto: no candidate passed data-plane prove',
      );
      expect(err.code, 'path_incompatible');
    });

    test('maps session PathIncompatible to path_incompatible', () {
      final err = vpnErrorFromSession(
        const VpnSessionSnapshot(
          phase: VpnSessionPhase.error,
          generation: 1,
          reason: VpnSessionReason.pathIncompatible,
          detail: 'path_incompatible: auto: no candidate passed data-plane prove',
        ),
      );
      expect(err.code, 'path_incompatible');
    });

    test('falls back when detail empty', () {
      final err = vpnErrorFromNativeDetail(
        null,
        fallbackMessage: 'Failed to start VPN service',
      );
      expect(err.code, isNull);
      expect(err.message, 'Failed to start VPN service');
    });
  });

  group('ownsConnectUi', () {
    test('is true during the walk', () {
      expect(
        const VpnSessionSnapshot(
          phase: VpnSessionPhase.proving,
          generation: 1,
        ).ownsConnectUi,
        isTrue,
      );
      expect(
        const VpnSessionSnapshot(
          phase: VpnSessionPhase.binding,
          generation: 1,
        ).ownsConnectUi,
        isTrue,
      );
      expect(
        const VpnSessionSnapshot(
          phase: VpnSessionPhase.tunUp,
          generation: 1,
        ).ownsConnectUi,
        isTrue,
      );
      expect(
        const VpnSessionSnapshot(
          phase: VpnSessionPhase.coreStarting,
          generation: 1,
        ).ownsConnectUi,
        isTrue,
      );
      expect(
        const VpnSessionSnapshot(
          phase: VpnSessionPhase.error,
          generation: 1,
          reason: VpnSessionReason.pathIncompatible,
        ).ownsConnectUi,
        isFalse,
      );
      expect(
        const VpnSessionSnapshot(
          phase: VpnSessionPhase.connectedHealthy,
          generation: 1,
        ).ownsConnectUi,
        isFalse,
      );
    });

    test('idle does not drop Connecting while walk or proving', () {
      expect(
        connectingIdleShouldDrop(
          walkActive: true,
          sessionOwnsUi: false,
          lastPhase: VpnSessionPhase.idle,
        ),
        isFalse,
      );
      expect(
        connectingIdleShouldDrop(
          walkActive: false,
          sessionOwnsUi: true,
          lastPhase: VpnSessionPhase.idle,
        ),
        isFalse,
      );
      expect(
        connectingIdleShouldDrop(
          walkActive: false,
          sessionOwnsUi: false,
          lastPhase: VpnSessionPhase.proving,
        ),
        isFalse,
      );
      expect(
        connectingIdleShouldDrop(
          walkActive: false,
          sessionOwnsUi: false,
          lastPhase: VpnSessionPhase.unknown,
        ),
        isFalse,
      );
      expect(
        connectingIdleShouldDrop(
          walkActive: false,
          sessionOwnsUi: false,
          lastPhase: VpnSessionPhase.idle,
        ),
        isTrue,
      );
    });

    test('ignoresNativeConnected only while proving', () {
      expect(
        const VpnSessionSnapshot(
          phase: VpnSessionPhase.proving,
          generation: 1,
        ).ignoresNativeConnected,
        isTrue,
      );
      expect(
        const VpnSessionSnapshot(
          phase: VpnSessionPhase.binding,
          generation: 1,
        ).ignoresNativeConnected,
        isFalse,
      );
      expect(
        const VpnSessionSnapshot(
          phase: VpnSessionPhase.tunUp,
          generation: 1,
        ).ignoresNativeConnected,
        isFalse,
      );
      expect(
        const VpnSessionSnapshot(
          phase: VpnSessionPhase.coreStarting,
          generation: 1,
        ).ignoresNativeConnected,
        isFalse,
      );
    });
  });
}
