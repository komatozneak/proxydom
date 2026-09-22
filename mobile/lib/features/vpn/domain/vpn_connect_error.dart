import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import '../../home/application/vpn_status.dart';
import '../data/vpn_session_snapshot.dart';

/// Machine code when native SOCKS HTTPS pre-connect probe fails.
const kVpnProbeFailedErrorCode = 'server_probe_failed';

/// Auto walk: no candidate passed data-plane prove.
const kVpnPathIncompatibleErrorCode = 'path_incompatible';

/// Control plane (DNS / TCP to the API) failed before any config was minted.
const kVpnApiUnreachableErrorCode = 'api_unreachable';

/// Why an Auto mint produced no config.
enum AutoMintSkipKind {
  /// DNS, connect, or timeout talking to the API.
  connection,

  /// HTTP / parse / other skip. Not a transport failure.
  other,
}

final RegExp _socksProbeFailPattern = RegExp(
  r'^(.+?)@([^:\s]+)(?::\d+)?:\s*SOCKS HTTPS probe failed\s*$',
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
      message: kVpnPathIncompatibleErrorCode,
      code: kVpnPathIncompatibleErrorCode,
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
      message: kVpnPathIncompatibleErrorCode,
      code: kVpnPathIncompatibleErrorCode,
    );
  }
  return vpnErrorFromNativeDetail(
    snap.detail,
    fallbackMessage: fallbackMessage,
  );
}

/// DNS / connect / timeout to the API. HTTP status errors are not this.
bool isControlPlaneTransportError(Object error) {
  if (error is SocketException || error is TimeoutException) return true;
  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
        return true;
      case DioExceptionType.unknown:
        final inner = error.error;
        return inner is SocketException || inner is TimeoutException;
      default:
        return false;
    }
  }
  return false;
}

/// Empty Auto mint: transport misses are [kVpnApiUnreachableErrorCode].
/// A data-plane path miss stays [kVpnPathIncompatibleErrorCode].
String autoMintEmptyFailCode(Iterable<AutoMintSkipKind> skips) {
  final list = skips.toList();
  if (list.isNotEmpty &&
      list.every((skip) => skip == AutoMintSkipKind.connection)) {
    return kVpnApiUnreachableErrorCode;
  }
  return kVpnPathIncompatibleErrorCode;
}
