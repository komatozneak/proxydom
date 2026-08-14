import '../../home/application/vpn_status.dart';
import '../data/vpn_session_snapshot.dart';

/// Machine code when native SOCKS HTTPS pre-connect probe fails.
const kVpnProbeFailedErrorCode = 'server_probe_failed';

final RegExp _socksProbeFailPattern = RegExp(
  r'^(.+?)@([^:\s]+):\s*SOCKS HTTPS probe failed\s*$',
  caseSensitive: false,
);

/// Parsed `id@host: SOCKS HTTPS probe failed` from [TeremokVpnService.failStart].
class SocksProbeFailure {
  const SocksProbeFailure({required this.nodeId, required this.host});

  final String nodeId;
  final String host;
}

SocksProbeFailure? parseSocksProbeFailure(String detail) {
  final trimmed = detail.trim();
  final match = _socksProbeFailPattern.firstMatch(trimmed);
  if (match == null) return null;
  final nodeId = match.group(1)?.trim() ?? '';
  final host = match.group(2)?.trim() ?? '';
  if (nodeId.isEmpty) return null;
  return SocksProbeFailure(nodeId: nodeId, host: host);
}

/// Map native [getLastError] text to a structured [VpnError] for Home UI.
VpnError vpnErrorFromNativeDetail(
  String? detail, {
  String fallbackMessage = 'Native VPN error',
}) {
  if (detail == null || detail.isEmpty) {
    return VpnError(message: fallbackMessage);
  }
  final probe = parseSocksProbeFailure(detail);
  if (probe != null) {
    return VpnError(
      code: kVpnProbeFailedErrorCode,
      message: probe.nodeId,
    );
  }
  if (detail.toLowerCase().contains('permission denied')) {
    return const VpnError(
      message: 'VPN permission denied',
      code: 'permission_denied',
    );
  }
  if (detail.toLowerCase().contains('path_incompatible')) {
    return const VpnError(
      message: 'Авто: ни один сервер не прошёл проверку',
      code: 'path_incompatible',
    );
  }
  return VpnError(message: 'vpn: $detail');
}

/// Map ADR 014 session Error / PathIncompatible to Home [VpnError].
VpnError vpnErrorFromSession(
  VpnSessionSnapshot snap, {
  String fallbackMessage = 'Native VPN error',
}) {
  if (snap.reason == VpnSessionReason.pathIncompatible) {
    return const VpnError(
      message: 'Авто: ни один сервер не прошёл проверку',
      code: 'path_incompatible',
    );
  }
  return vpnErrorFromNativeDetail(
    snap.detail,
    fallbackMessage: fallbackMessage,
  );
}
