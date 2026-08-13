import '../data/node_display.dart';
import '../data/vpn_config.dart';
import '../data/vpn_node.dart';
import '../data/vpn_session_snapshot.dart';

/// Cellular NIC prefixes (kept here so this file compiles without ADR 014 error map).
bool _isCellularIface(String? iface) {
  if (iface == null || iface.isEmpty) return false;
  final lower = iface.toLowerCase();
  return lower.startsWith('rmnet') ||
      lower.startsWith('ccmni') ||
      lower.startsWith('wwan') ||
      lower.startsWith('pdp');
}

/// Hidden TrustTunnel node for EU Xray PathPlan fail (ADR 006 addendum 2026-08-13).
const kEuTtFallbackNodeId = 'eu-tt-1';

/// True when a catalog row must stay off Locations / Auto (silent fallback only).
bool isHiddenEuTtFallbackNode(VpnNode node) => node.id == kEuTtFallbackNodeId;

/// Catalog / mint id for free Eastern Europe Xray.
const kEuPrimaryNodeId = 'eu-primary';

/// True when this Connect may silently start [kEuTtFallbackNodeId].
///
/// Only Europe Xray (or Auto that minted EU). Never US / YouTube / already-TT.
bool shouldSilentEuTtFallback({
  required VpnSessionSnapshot snap,
  String? selectedNodeId,
  String? selectedProtocol,
  VpnActiveCore? activeCore,
  bool quotaExceeded = false,
}) {
  if (quotaExceeded) return false;
  if (selectedProtocol == kVpnNodeProtocolTrusttunnel) return false;
  if (activeCore == VpnActiveCore.trusttunnel) return false;
  if (selectedNodeId != null &&
      selectedNodeId.isNotEmpty &&
      selectedNodeId != kRegionAutoId &&
      selectedNodeId != kEuPrimaryNodeId &&
      selectedNodeId != kEuTtFallbackNodeId) {
    return false;
  }
  if (snap.reason == VpnSessionReason.pathIncompatible ||
      snap.reason == VpnSessionReason.egressTimeout) {
    return true;
  }
  return snap.phase == VpnSessionPhase.error &&
      (_isCellularIface(snap.underlyingIface) ||
          snap.transport == VpnPathTransport.cellular);
}
