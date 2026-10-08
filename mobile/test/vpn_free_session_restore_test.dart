import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/features/vpn/data/vpn_session_snapshot.dart';

void main() {
  test('free session skips hydration only while already connected', () {
    expect(
      shouldSkipFreeSessionHydration(
        freeSessionOpen: true,
        uiConnecting: false,
      ),
      isTrue,
    );
    expect(
      shouldSkipFreeSessionHydration(
        freeSessionOpen: true,
        uiConnecting: true,
      ),
      isFalse,
    );
    expect(
      shouldSkipFreeSessionHydration(
        freeSessionOpen: false,
        uiConnecting: true,
      ),
      isFalse,
    );
  });

  test('recover inside one free session ends connected', () {
    var nest = FreeSessionNest.connected;
    const phases = <VpnSessionPhase>[
      VpnSessionPhase.connectedHealthy,
      VpnSessionPhase.connectedDegraded,
      VpnSessionPhase.connectedDegraded,
      VpnSessionPhase.binding,
      VpnSessionPhase.connectedHealthy,
    ];
    final seen = <FreeSessionNest>[];
    for (final phase in phases) {
      nest = freeSessionNestAfterPhase(
        nest: nest,
        phase: phase,
        freeSessionOpen: true,
      );
      seen.add(nest);
    }
    expect(seen, [
      FreeSessionNest.connected,
      FreeSessionNest.connected,
      FreeSessionNest.connected,
      FreeSessionNest.connecting,
      FreeSessionNest.connected,
    ]);
  });

  test('binding then connected without a free session still connects', () {
    final nest = freeSessionNestAfterPhase(
      nest: freeSessionNestAfterPhase(
        nest: FreeSessionNest.other,
        phase: VpnSessionPhase.binding,
        freeSessionOpen: false,
      ),
      phase: VpnSessionPhase.connectedHealthy,
      freeSessionOpen: false,
    );
    expect(nest, FreeSessionNest.connected);
  });
}