import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/features/vpn/data/vpn_session_snapshot.dart';

void main() {
  group('cold-start idle demotion gate', () {
    test('Connected + unknown phase must not demote after sync', () {
      expect(
        nativeIdleMustNotDemote(
          walkActive: false,
          sessionOwnsUi: false,
          lastPhase: VpnSessionPhase.unknown,
          uiConnected: true,
        ),
        isTrue,
      );
    });

    test('gate idle until native sync completes', () {
      expect(
        nativeIdleMustNotDemote(
          walkActive: false,
          sessionOwnsUi: false,
          lastPhase: VpnSessionPhase.idle,
          nativeSyncComplete: false,
        ),
        isTrue,
      );
    });

    test('real idle after sync demotes when not connected UI', () {
      expect(
        nativeIdleMustNotDemote(
          walkActive: false,
          sessionOwnsUi: false,
          lastPhase: VpnSessionPhase.idle,
          uiConnected: false,
          nativeSyncComplete: true,
        ),
        isFalse,
      );
    });

    test('connectedHealthy still protects', () {
      expect(
        nativeIdleMustNotDemote(
          walkActive: false,
          sessionOwnsUi: false,
          lastPhase: VpnSessionPhase.connectedHealthy,
          uiConnected: true,
        ),
        isTrue,
      );
    });
  });
}
