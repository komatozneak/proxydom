import 'dart:convert';

/// Typed VPN session snapshot from native EventChannel `proxydom/vpn/session`
///.
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
  nodeHandshake,
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

  /// Auto SOCKS hops: ignore native connected (no TUN yet / Always-on leftover).
  bool get ignoresNativeConnected => phase == VpnSessionPhase.proving;

  /// Auto/manual walk: Flutter must ignore intermediate native error/idle.
  bool get ownsConnectUi =>
      phase == VpnSessionPhase.binding ||
      phase == VpnSessionPhase.proving ||
      phase == VpnSessionPhase.tunUp ||
      phase == VpnSessionPhase.coreStarting;

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

/// `VpnNativeStatus.idle` / `getStatus()` is not SoT during walk or a live session.
///
/// Binding/Proving often report idle while TUN is coming up. ConnectedHealthy
/// can still flap idle under Always-on / lockdown — do not demote Nest.
/// After an intentional Nest stop ([userStopping]) Idle is real — demote.
bool nativeIdleMustNotDemote({
  required bool walkActive,
  required bool sessionOwnsUi,
  required VpnSessionPhase lastPhase,
  bool userStopping = false,
  bool uiConnected = false,
  bool nativeSyncComplete = true,
}) {
  if (userStopping) return false;
  if (!nativeSyncComplete) return true;
  if (walkActive || sessionOwnsUi) return true;
  // Cold start: sync painted Connected before EventChannel seeded phase.
  if (uiConnected && lastPhase == VpnSessionPhase.unknown) return true;
  switch (lastPhase) {
    case VpnSessionPhase.binding:
    case VpnSessionPhase.tunUp:
    case VpnSessionPhase.coreStarting:
    case VpnSessionPhase.proving:
    case VpnSessionPhase.connectedHealthy:
    case VpnSessionPhase.connectedDegraded:
      return true;
    case VpnSessionPhase.stopping:
    case VpnSessionPhase.idle:
    case VpnSessionPhase.error:
    case VpnSessionPhase.unknown:
      return false;
  }
}

/// Session EventChannel can replay Idle/Unknown after Binding/Proving/Connected
/// (Auto hop teardownCores, engine reconnect). Keep the last live phase.
/// Stopping/Error idle is real teardown — do not ignore.
bool shouldIgnoreRegressiveIdleSnapshot({
  required VpnSessionPhase incoming,
  required VpnSessionPhase lastPhase,
  required bool walkActive,
  required bool sessionOwnsUi,
  bool userStopping = false,
}) {
  if (incoming != VpnSessionPhase.idle && incoming != VpnSessionPhase.unknown) {
    return false;
  }
  if (userStopping) return false;
  if (walkActive || sessionOwnsUi) return true;
  switch (lastPhase) {
    case VpnSessionPhase.binding:
    case VpnSessionPhase.tunUp:
    case VpnSessionPhase.coreStarting:
    case VpnSessionPhase.proving:
    case VpnSessionPhase.connectedHealthy:
    case VpnSessionPhase.connectedDegraded:
      return true;
    case VpnSessionPhase.stopping:
    case VpnSessionPhase.idle:
    case VpnSessionPhase.error:
    case VpnSessionPhase.unknown:
      return false;
  }
}

/// Native/session idle must not paint Nest rest while Auto/manual walk is open.
bool connectingIdleShouldDrop({
  required bool walkActive,
  required bool sessionOwnsUi,
  required VpnSessionPhase lastPhase,
  bool userStopping = false,
}) {
  if (nativeIdleMustNotDemote(
    walkActive: walkActive,
    sessionOwnsUi: sessionOwnsUi,
    lastPhase: lastPhase,
    userStopping: userStopping,
  )) {
    return false;
  }
  return lastPhase == VpnSessionPhase.idle || userStopping;
}

/// Free-session flag skips a second hydration. It does not freeze Connecting.
///
/// A connected snapshot while the Nest is already Connected must not open
/// another session. The same snapshot while the Nest is Connecting (native
/// recover published Binding, then ConnectedHealthy) has to paint Connected
/// again. [uiConnecting] is the Nest, not the native phase.
bool shouldSkipFreeSessionHydration({
  required bool freeSessionOpen,
  required bool uiConnecting,
}) =>
    freeSessionOpen && !uiConnecting;

/// Paint used by [freeSessionNestAfterPhase]. Not a [VpnStatus].
enum FreeSessionNest { connecting, connected, other }

/// One session phase against an already-open free session.
///
/// Walk phases (`ownsConnectUi`) drop the Nest to Connecting. Dead is still
/// [VpnSessionPhase.connectedDegraded], so it does not drop the Nest; the
/// Binding that follows the recover does. The next connected phase paints
/// Connected again.
FreeSessionNest freeSessionNestAfterPhase({
  required FreeSessionNest nest,
  required VpnSessionPhase phase,
  required bool freeSessionOpen,
}) {
  final ownsWalk = switch (phase) {
    VpnSessionPhase.binding ||
    VpnSessionPhase.tunUp ||
    VpnSessionPhase.coreStarting ||
    VpnSessionPhase.proving =>
      true,
    _ => false,
  };
  if (ownsWalk) return FreeSessionNest.connecting;
  final snapshotConnected = phase == VpnSessionPhase.connectedHealthy ||
      phase == VpnSessionPhase.connectedDegraded;
  if (!snapshotConnected) return nest;
  if (shouldSkipFreeSessionHydration(
    freeSessionOpen: freeSessionOpen,
    uiConnecting: nest == FreeSessionNest.connecting,
  )) {
    return nest;
  }
  return FreeSessionNest.connected;
}

/// Nest Connected paint: abort stale restore-connect and require a live TUN
/// unless Auto/manual walk still owns the UI.
bool shouldRefuseEnterConnected({
  required bool sessionProving,
  required int? connectGen,
  required int currentGen,
  required bool walkActive,
  required bool sessionOwnsUi,
  required bool nativeConnected,
  bool userStopping = false,
}) {
  if (userStopping) return true;
  if (sessionProving) return true;
  if (connectGen != null && connectGen != currentGen) return true;
  if (walkActive || sessionOwnsUi) return false;
  return !nativeConnected;
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
    case 'NodeHandshake':
      return VpnSessionReason.nodeHandshake;
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

/// Home Wi-Fi path: native `wlan*` / `wifi*` or PathPlan transport `wifi`.
bool isWifiUnderlying({
  String? iface,
  VpnPathTransport transport = VpnPathTransport.unknown,
}) {
  if (transport == VpnPathTransport.wifi) return true;
  if (transport == VpnPathTransport.cellular) return false;
  final lower = iface?.trim().toLowerCase() ?? '';
  if (lower.isEmpty || lower == '(unknown)' || lower == 'unknown') {
    return false;
  }
  return lower.startsWith('wlan') || lower.startsWith('wifi');
}

/// One PathIncompatible Auto retry on Wi-Fi. Never loops; never after Nest stop.
bool shouldRetryAutoOnWifi({
  required bool alreadyRetried,
  required bool userStopping,
  required bool isWifi,
}) {
  if (alreadyRetried || userStopping || !isWifi) return false;
  return true;
}

/// What to do with a tunnel whose exit address could not be read.
///
/// An empty IP is `egress_unknown`. It is a journal fact. It does not stop
/// a session that already carries TCP.
class EgressProbeDecision {
  const EgressProbeDecision({
    required this.stopSession,
    required this.result,
  });

  final bool stopSession;

  /// `ok` when an address was read, otherwise `egress_unknown`.
  final String result;
}

EgressProbeDecision decideEgressProbe(String? ip) {
  final shown = ip?.trim() ?? '';
  if (shown.isEmpty) {
    return const EgressProbeDecision(
      stopSession: false,
      result: 'egress_unknown',
    );
  }
  return const EgressProbeDecision(stopSession: false, result: 'ok');
}

/// One re-read of the pasted document after the node refused our secret.
///
/// Reissuing a document rotates every node password, so a cached config
/// keeps presenting a stale one and the node masquerades (405). Never
/// loops: one refresh per connect attempt, and never after Nest stop or
/// when the line was pasted bare (no source URL to re-read).
bool shouldRefreshAfterAuthRefusal({
  required bool alreadyRefreshed,
  required bool userStopping,
  required bool hasSourceUrl,
}) {
  if (alreadyRefreshed || userStopping || !hasSourceUrl) return false;
  return true;
}
