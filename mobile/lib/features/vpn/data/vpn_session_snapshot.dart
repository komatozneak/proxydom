import 'dart:convert';

/// Typed VPN session snapshot from native EventChannel `teremok/vpn/session`
/// (ADR 014 — client Connect SoT).
enum VpnSessionPhase {
  idle,
  binding,
  tunUp,
  coreStarting,
  proving,
  connectedHealthy,
  connectedDegraded,
  stopping,
  error,
  unknown,
}

enum VpnSessionReason {
  none,
  underlyingBad,
  dialFail,
  egressTimeout,
  egressOk,
  degraded,
  dead,
  cancelled,
  revoked,
  protectFail,
  invalidParams,
  pathIncompatible,
  unknown,
}

/// PathPlan transport from native (wifi | cellular | unknown).
enum VpnPathTransport {
  wifi,
  cellular,
  unknown,
}

final class VpnSessionSnapshot {
  const VpnSessionSnapshot({
    required this.phase,
    required this.generation,
    this.reason = VpnSessionReason.none,
    this.legacyStatus,
    this.candidateId,
    this.candidateHost,
    this.underlyingIface,
    this.transport = VpnPathTransport.unknown,
    this.rttMs,
    this.detail,
  });

  final VpnSessionPhase phase;
  final int generation;
  final VpnSessionReason reason;
  final String? legacyStatus;
  final String? candidateId;
  final String? candidateHost;
  final String? underlyingIface;
  final VpnPathTransport transport;
  final int? rttMs;
  final String? detail;

  bool get isConnected =>
      phase == VpnSessionPhase.connectedHealthy ||
      phase == VpnSessionPhase.connectedDegraded;

  bool get isTerminalForConnect =>
      isConnected || phase == VpnSessionPhase.error;

  bool get isProving => phase == VpnSessionPhase.proving;

  factory VpnSessionSnapshot.fromJson(Map<String, dynamic> json) {
    return VpnSessionSnapshot(
      phase: parseVpnSessionPhase(json['phase'] as String?),
      generation: (json['generation'] as num?)?.toInt() ?? 0,
      reason: parseVpnSessionReason(json['reason'] as String?),
      legacyStatus: json['legacyStatus'] as String?,
      candidateId: json['candidateId'] as String?,
      candidateHost: json['candidateHost'] as String?,
      underlyingIface: json['underlyingIface'] as String?,
      transport: parseVpnPathTransport(json['transport'] as String?),
      rttMs: (json['rttMs'] as num?)?.toInt(),
      detail: json['detail'] as String?,
    );
  }

  factory VpnSessionSnapshot.fromEvent(dynamic event) {
    if (event is String) {
      final decoded = jsonDecode(event);
      if (decoded is Map<String, dynamic>) {
        return VpnSessionSnapshot.fromJson(decoded);
      }
      if (decoded is Map) {
        return VpnSessionSnapshot.fromJson(
          decoded.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
    }
    if (event is Map<String, dynamic>) {
      return VpnSessionSnapshot.fromJson(event);
    }
    if (event is Map) {
      return VpnSessionSnapshot.fromJson(
        event.map((k, v) => MapEntry(k.toString(), v)),
      );
    }
    return const VpnSessionSnapshot(
      phase: VpnSessionPhase.unknown,
      generation: 0,
    );
  }
}

VpnSessionPhase parseVpnSessionPhase(String? raw) {
  if (raw == null || raw.isEmpty) return VpnSessionPhase.unknown;
  switch (raw) {
    case 'Idle':
      return VpnSessionPhase.idle;
    case 'Binding':
      return VpnSessionPhase.binding;
    case 'TunUp':
      return VpnSessionPhase.tunUp;
    case 'CoreStarting':
      return VpnSessionPhase.coreStarting;
    case 'Proving':
      return VpnSessionPhase.proving;
    case 'ConnectedHealthy':
      return VpnSessionPhase.connectedHealthy;
    case 'ConnectedDegraded':
      return VpnSessionPhase.connectedDegraded;
    case 'Stopping':
      return VpnSessionPhase.stopping;
    case 'Error':
      return VpnSessionPhase.error;
    default:
      return VpnSessionPhase.unknown;
  }
}

VpnSessionReason parseVpnSessionReason(String? raw) {
  if (raw == null || raw.isEmpty || raw == 'None') {
    return VpnSessionReason.none;
  }
  switch (raw) {
    case 'UnderlyingBad':
      return VpnSessionReason.underlyingBad;
    case 'DialFail':
      return VpnSessionReason.dialFail;
    case 'EgressTimeout':
      return VpnSessionReason.egressTimeout;
    case 'EgressOk':
      return VpnSessionReason.egressOk;
    case 'Degraded':
      return VpnSessionReason.degraded;
    case 'Dead':
      return VpnSessionReason.dead;
    case 'Cancelled':
      return VpnSessionReason.cancelled;
    case 'Revoked':
      return VpnSessionReason.revoked;
    case 'ProtectFail':
      return VpnSessionReason.protectFail;
    case 'InvalidParams':
      return VpnSessionReason.invalidParams;
    case 'PathIncompatible':
      return VpnSessionReason.pathIncompatible;
    case 'Unknown':
      return VpnSessionReason.unknown;
    default:
      return VpnSessionReason.unknown;
  }
}

VpnPathTransport parseVpnPathTransport(String? raw) {
  switch (raw?.toLowerCase()) {
    case 'wifi':
      return VpnPathTransport.wifi;
    case 'cellular':
      return VpnPathTransport.cellular;
    default:
      return VpnPathTransport.unknown;
  }
}
