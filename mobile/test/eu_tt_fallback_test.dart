import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/features/vpn/data/node_display.dart';
import 'package:teremok_connect/features/vpn/data/vpn_config.dart';
import 'package:teremok_connect/features/vpn/data/vpn_node.dart';
import 'package:teremok_connect/features/vpn/data/vpn_session_snapshot.dart';
import 'package:teremok_connect/features/vpn/domain/eu_tt_fallback.dart';

void main() {
  const fail = VpnSessionSnapshot(
    phase: VpnSessionPhase.error,
    generation: 2,
    reason: VpnSessionReason.pathIncompatible,
    transport: VpnPathTransport.cellular,
    underlyingIface: 'rmnet1',
  );

  test('EU xray / auto may silent-fallback', () {
    expect(
      shouldSilentEuTtFallback(snap: fail, selectedNodeId: kEuPrimaryNodeId),
      isTrue,
    );
    expect(
      shouldSilentEuTtFallback(snap: fail, selectedNodeId: kRegionAutoId),
      isTrue,
    );
    expect(
      shouldSilentEuTtFallback(snap: fail, selectedNodeId: null),
      isTrue,
    );
  });

  test('US and YouTube never silent-fallback', () {
    expect(
      shouldSilentEuTtFallback(snap: fail, selectedNodeId: 'us-geo-1'),
      isFalse,
    );
    expect(
      shouldSilentEuTtFallback(snap: fail, selectedNodeId: 'al-youtube'),
      isFalse,
    );
    expect(
      shouldSilentEuTtFallback(
        snap: fail,
        selectedNodeId: kEuPrimaryNodeId,
        selectedProtocol: kVpnNodeProtocolTrusttunnel,
      ),
      isFalse,
    );
    expect(
      shouldSilentEuTtFallback(
        snap: fail,
        selectedNodeId: kEuPrimaryNodeId,
        activeCore: VpnActiveCore.trusttunnel,
      ),
      isFalse,
    );
  });

  test('hidden fallback id is filtered from catalog', () {
    const hidden = VpnNode(
      id: kEuTtFallbackNodeId,
      label: 'EU',
      host: '217.60.3.9',
      port: 443,
      status: 'connected',
      isDefault: false,
      protocol: kVpnNodeProtocolTrusttunnel,
    );
    const eu = VpnNode(
      id: kEuPrimaryNodeId,
      label: 'EU',
      host: '204.11.2.216',
      port: 443,
      status: 'connected',
      isDefault: true,
    );
    expect(isHiddenEuTtFallbackNode(hidden), isTrue);
    expect(isHiddenEuTtFallbackNode(eu), isFalse);
  });

  test('quota_exceeded blocks silent EU TT', () {
    expect(
      shouldSilentEuTtFallback(
        snap: fail,
        selectedNodeId: kEuPrimaryNodeId,
        quotaExceeded: true,
      ),
      isFalse,
    );
  });

  test('dial fail is not a path fallback', () {
    const snap = VpnSessionSnapshot(
      phase: VpnSessionPhase.error,
      generation: 1,
      reason: VpnSessionReason.dialFail,
    );
    expect(
      shouldSilentEuTtFallback(snap: snap, selectedNodeId: kEuPrimaryNodeId),
      isFalse,
    );
  });
}
