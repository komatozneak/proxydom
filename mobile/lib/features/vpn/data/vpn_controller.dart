import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../settings/data/split_tunnel_prefs.dart';
import 'vpn_config.dart';
import 'vpn_route_policy.dart';
import 'vpn_service_config.dart';
import 'vpn_session_snapshot.dart';

/// Bridge between Flutter UI and Android VpnService (Hysteria2, ADR 018).
///
/// Uses [MethodChannel] `teremok/vpn` for commands and [EventChannel]
/// `teremok/vpn/status` for live status updates from native code.
class VpnController {
  VpnController._();
  static final VpnController instance = VpnController._();

  static const _methodChannel = MethodChannel('teremok/vpn');
  static const _eventChannel = EventChannel('teremok/vpn/status');
  static const _sessionEventChannel = EventChannel('teremok/vpn/session');
  static const _trafficEventChannel = EventChannel('teremok/vpn/traffic');
  static const _pingEventChannel = EventChannel('teremok/vpn/ping');

  static const Duration stopTimeout = Duration(seconds: 5);

  Stream<VpnNativeStatus>? _statusStream;
  Stream<VpnSessionSnapshot>? _sessionStream;
  Stream<VpnTrafficStats>? _trafficStream;
  Stream<int?>? _pingStream;

  /// Build MethodChannel params for one minted Hy2 config.
  Future<String> buildStartParamsJson(
    VpnConfig config, {
    String? displayLabel,
    String? catalogNodeId,
  }) async {
    final profile = config.hysteriaProfile;
    if (!config.isHysteriaSession || profile == null) {
      throw VpnControllerException('hy2_provision_failed');
    }
    final disallowedApps =
        (await SplitTunnelPrefs.loadDisallowedPackages()).toList()..sort();
    final directSuffixes = stripForceProxySuffixes(
      await SplitTunnelPrefs.enabledDomainSuffixes(),
    );
    return jsonEncode({
      'schemaVersion': 2,
      'vpnCore': 'hysteria',
      'autoJob': true,
      'sessionName': kVpnBrandSessionName,
      'displayLabel': (displayLabel?.trim().isNotEmpty == true)
          ? displayLabel!.trim()
          : kVpnBrandSessionName,
      'outboundType': 'hysteria2',
      'hysteriaServer': profile.server,
      'hysteriaAuth': profile.auth,
      'hysteriaSni': profile.sni,
      'hysteriaSocksListen': profile.socksListen,
      'hysteriaNodeId': profile.nodeId,
      if (catalogNodeId != null) 'autoNodeId': catalogNodeId,
      if (profile.bandwidthUp != null)
        'hysteriaBandwidthUp': profile.bandwidthUp,
      if (profile.bandwidthDown != null)
        'hysteriaBandwidthDown': profile.bandwidthDown,
      'controlPlaneHosts': VpnServiceConfig.controlPlaneHostsOf(),
      if (disallowedApps.isNotEmpty) 'disallowedApplications': disallowedApps,
      if (directSuffixes.isNotEmpty) 'directDomainSuffixes': directSuffixes,
    });
  }

  /// Start Hy2 VPN with [VpnConfig.hysteriaProfile].
  Future<bool> start(VpnConfig config, {String? displayLabel}) async {
    final profile = config.hysteriaProfile;
    if (profile == null) {
      throw VpnControllerException('hy2_provision_failed');
    }
    return startHysteria(profile, displayLabel: displayLabel);
  }

  /// Auto: sequential data-plane prove over already-minted [paramsJson] rows.
  Future<bool> startAuto(List<String> paramsJsonList) async {
    if (paramsJsonList.isEmpty) {
      throw VpnControllerException('auto pool empty');
    }
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        'startAuto',
        {'candidatesJson': paramsJsonList},
      );
      if (result == true) {
        await SplitTunnelPrefs.markApplied();
      }
      return result ?? false;
    } on PlatformException catch (e) {
      throw VpnControllerException('auto start failed: ${e.code} ${e.message}');
    }
  }

  /// Start Hysteria2 core (ADR 015). Native proves via local SOCKS, not QUIC-up.
  Future<bool> startHysteria(
    HysteriaProfile profile, {
    String? displayLabel,
  }) async {
    try {
      final disallowedApps =
          (await SplitTunnelPrefs.loadDisallowedPackages()).toList()..sort();
      final directSuffixes = stripForceProxySuffixes(
        await SplitTunnelPrefs.enabledDomainSuffixes(),
      );
      final paramsJson = jsonEncode({
        'schemaVersion': 2,
        'vpnCore': 'hysteria',
        'sessionName': kVpnBrandSessionName,
        'displayLabel': (displayLabel?.trim().isNotEmpty == true)
            ? displayLabel!.trim()
            : kVpnBrandSessionName,
        'outboundType': 'hysteria2',
        'hysteriaServer': profile.server,
        'hysteriaAuth': profile.auth,
        'hysteriaSni': profile.sni,
        'hysteriaSocksListen': profile.socksListen,
        'hysteriaNodeId': profile.nodeId,
        if (profile.bandwidthUp != null)
          'hysteriaBandwidthUp': profile.bandwidthUp,
        if (profile.bandwidthDown != null)
          'hysteriaBandwidthDown': profile.bandwidthDown,
        'controlPlaneHosts': VpnServiceConfig.controlPlaneHostsOf(),
        if (disallowedApps.isNotEmpty) 'disallowedApplications': disallowedApps,
        if (directSuffixes.isNotEmpty) 'directDomainSuffixes': directSuffixes,
      });

      final result = await _methodChannel.invokeMethod<bool>(
        'start',
        {'paramsJson': paramsJson},
      );
      if (result == true) {
        await SplitTunnelPrefs.markApplied();
      }
      return result ?? false;
    } on PlatformException catch (e) {
      throw VpnControllerException(
        'hysteria start failed: ${e.code} ${e.message}',
      );
    }
  }

  Future<bool> stop() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('stop').timeout(
        stopTimeout,
        onTimeout: () {
          throw VpnControllerException(
            'stop timeout after ${stopTimeout.inSeconds}s',
          );
        },
      );
      return result ?? false;
    } on TimeoutException catch (e) {
      throw VpnControllerException('stop timeout: $e');
    } on PlatformException catch (e) {
      throw VpnControllerException('stop failed: ${e.code} ${e.message}');
    }
  }

  /// Logout / identity change: stop the tunnel AND wipe persisted native
  /// session params (dataplane passwords) so the QS tile / Always-on restart
  /// cannot resurrect the previous account's VPN.
  Future<bool> wipeSession() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('wipeSession');
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<VpnNativeStatus> getStatus() async {
    try {
      final result = await _methodChannel.invokeMethod<String>('getStatus');
      return parseVpnNativeStatus(result);
    } on PlatformException {
      return VpnNativeStatus.unknown;
    } on MissingPluginException {
      return VpnNativeStatus.unknown;
    }
  }

  Future<bool> hasActiveSession() async {
    try {
      final result =
          await _methodChannel.invokeMethod<bool>('hasActiveSession');
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<String?> getLastError() async {
    try {
      return await _methodChannel.invokeMethod<String>('getLastError');
    } on PlatformException {
      return null;
    }
  }

  /// Last N lines of VPN core stderr (Xray / legacy sing-box working dir).
  Future<String?> getVpnCoreStderrTail({int maxLines = 400}) async {
    try {
      return await _methodChannel.invokeMethod<String>(
        'getSingBoxStderrTail',
        {'maxLines': maxLines},
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Compat alias for diagnostics / older call sites.
  Future<String?> getSingBoxStderrTail({int maxLines = 400}) =>
      getVpnCoreStderrTail(maxLines: maxLines);

  Future<String?> getUnderlyingNetworkInterface() async {
    try {
      return await _methodChannel.invokeMethod<String>(
        'getUnderlyingNetworkInterface',
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<bool> isLockdownEnabled() async {
    return (await queryLockdownState()) == VpnLockdownState.enabled;
  }

  Future<VpnLockdownState> queryLockdownState() async {
    try {
      final raw =
          await _methodChannel.invokeMethod<dynamic>('isLockdownEnabled');
      return _mapLockdownNative(raw);
    } on PlatformException {
      return VpnLockdownState.unavailable;
    } on MissingPluginException {
      return VpnLockdownState.unavailable;
    }
  }

  static VpnLockdownState _mapLockdownNative(dynamic raw) {
    if (raw == null) return VpnLockdownState.unavailable;
    if (raw is bool) {
      return raw ? VpnLockdownState.enabled : VpnLockdownState.disabled;
    }
    if (raw is Map) {
      final lockdown = raw['lockdown'];
      final alwaysOn = raw['alwaysOn'];
      if (lockdown == true) return VpnLockdownState.enabled;
      if (lockdown == false && alwaysOn == true) {
        return VpnLockdownState.alwaysOnOnly;
      }
      if (lockdown == false) return VpnLockdownState.disabled;
      if (alwaysOn == true) return VpnLockdownState.alwaysOnOnly;
      return VpnLockdownState.unavailable;
    }
    return VpnLockdownState.unavailable;
  }

  Future<bool> openVpnSettings() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('openVpnSettings');
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Detect a blocking foreign VPN: Always-on / lockdown / live TUN (Android).
  Future<VpnConflictInfo> queryVpnConflict() async {
    try {
      final raw = await _methodChannel.invokeMethod<dynamic>('getVpnConflict');
      return VpnConflictInfo.fromNative(raw);
    } on PlatformException {
      return VpnConflictInfo.none;
    } on MissingPluginException {
      return VpnConflictInfo.none;
    }
  }

  Future<bool> requestNotificationPermission() async {
    try {
      final result = await _methodChannel
          .invokeMethod<bool>('requestNotificationPermission');
      return result ?? true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return true;
    }
  }

  Stream<VpnNativeStatus> get statusStream {
    _statusStream ??= _eventChannel.receiveBroadcastStream().map((event) {
      if (event is String) {
        return parseVpnNativeStatus(event);
      }
      return VpnNativeStatus.unknown;
    }).handleError((_) {
      return VpnNativeStatus.unknown;
    });
    return _statusStream!;
  }

  Stream<VpnSessionSnapshot> get sessionStream {
    _sessionStream ??= _sessionEventChannel
        .receiveBroadcastStream()
        .map(VpnSessionSnapshot.fromEvent)
        .handleError((_) {
      return const VpnSessionSnapshot(
        phase: VpnSessionPhase.unknown,
        generation: 0,
      );
    });
    return _sessionStream!;
  }

  Stream<VpnTrafficStats> get trafficStream {
    _trafficStream ??=
        _trafficEventChannel.receiveBroadcastStream().map((event) {
      if (event is Map) {
        final down = event['downlinkBps'];
        final up = event['uplinkBps'];
        return VpnTrafficStats(
          downlinkBps: (down is num) ? down.toInt() : 0,
          uplinkBps: (up is num) ? up.toInt() : 0,
        );
      }
      return const VpnTrafficStats.zero();
    }).handleError((_) => const VpnTrafficStats.zero());
    return _trafficStream!;
  }

  Stream<int?> get pingStream {
    _pingStream ??= _pingEventChannel
        .receiveBroadcastStream()
        .map(parsePingEventMs)
        .handleError((_) => null);
    return _pingStream!;
  }

  Future<bool> requestPermission() async {
    try {
      final result =
          await _methodChannel.invokeMethod<bool>('requestPermission');
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      // iOS before channel parity / hot-restart: do not block Connect.
      // System VPN consent still happens on startVPNTunnel.
      return true;
    }
  }
}

/// Parses EventChannel `teremok/vpn/ping` payloads.
///
/// Explicit `delayMs: null` clears a stale RTT (native consecutive probe fail).
@visibleForTesting
int? parsePingEventMs(dynamic event) {
  if (event is Map) {
    if (!event.containsKey('delayMs')) return null;
    final ms = event['delayMs'];
    if (ms == null) return null;
    if (ms is num) {
      final v = ms.toInt();
      if (v >= 30 && v <= 5000) return v;
    }
    return null;
  }
  if (event is num) {
    final v = event.toInt();
    if (v >= 30 && v <= 5000) return v;
  }
  return null;
}

enum VpnLockdownState {
  enabled,
  alwaysOnOnly,
  disabled,
  unavailable,
}

enum VpnNativeStatus {
  unknown,
  idle,
  preparing,
  connecting,
  connected,
  disconnecting,
  revoked,
  error,
}

/// Maps Android legacy status strings. `probing` is SessionPhase.Proving.
VpnNativeStatus parseVpnNativeStatus(String? raw) {
  if (raw == null || raw.isEmpty) return VpnNativeStatus.unknown;
  if (raw == 'probing') return VpnNativeStatus.connecting;
  return VpnNativeStatus.values.firstWhere(
    (s) => s.name == raw,
    orElse: () => VpnNativeStatus.unknown,
  );
}

final class VpnTrafficStats {
  const VpnTrafficStats({
    required this.downlinkBps,
    required this.uplinkBps,
  });

  const VpnTrafficStats.zero()
      : downlinkBps = 0,
        uplinkBps = 0;

  final int downlinkBps;
  final int uplinkBps;

  static String formatSpeed(int bytesPerSecond) {
    if (bytesPerSecond <= 0) return '0 B/s';
    const kib = 1024.0;
    const mib = kib * 1024.0;
    if (bytesPerSecond >= mib) {
      return '${(bytesPerSecond / mib).toStringAsFixed(2)} MiB/s';
    }
    if (bytesPerSecond >= kib) {
      return '${(bytesPerSecond / kib).toStringAsFixed(2)} KiB/s';
    }
    return '$bytesPerSecond B/s';
  }
}

class VpnControllerException implements Exception {
  VpnControllerException(this.message);
  final String message;

  @override
  String toString() => 'VpnControllerException: $message';
}

/// Snapshot from Android `getVpnConflict` (foreign Always-on / live VPN).
final class VpnConflictInfo {
  const VpnConflictInfo({
    required this.foreignAlwaysOn,
    this.packageName,
    this.appLabel,
    this.lockdown,
    this.foreignVpnActive = false,
  });

  static const none = VpnConflictInfo(foreignAlwaysOn: false);

  final bool foreignAlwaysOn;
  final String? packageName;
  final String? appLabel;
  final bool? lockdown;
  final bool foreignVpnActive;

  /// Prefer resolved label; fall back to package name.
  String get displayName {
    final label = appLabel?.trim();
    if (label != null && label.isNotEmpty) return label;
    final pkg = packageName?.trim();
    if (pkg != null && pkg.isNotEmpty) return pkg;
    return 'VPN';
  }

  factory VpnConflictInfo.fromNative(dynamic raw) {
    if (raw is! Map) return VpnConflictInfo.none;
    final map = Map<Object?, Object?>.from(raw);
    final foreign = map['foreignAlwaysOn'] == true;
    final foreignVpn = map['foreignVpnActive'] == true;
    final lockdownRaw = map['lockdown'];
    final lockdown = lockdownRaw is bool ? lockdownRaw : null;
    // Native already folds foreign lockdown into [foreignAlwaysOn]. Do not
    // OR lockdown here: leftover lockdown while we occupy the TUN would
    // look like a conflict and hide "already connected".
    final blocking = foreign || foreignVpn;
    if (!blocking) return VpnConflictInfo.none;
    return VpnConflictInfo(
      foreignAlwaysOn: true,
      foreignVpnActive: foreignVpn,
      packageName: map['packageName']?.toString(),
      appLabel: map['appLabel']?.toString(),
      lockdown: lockdown,
    );
  }
}
