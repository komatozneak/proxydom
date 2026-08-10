import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../core/diagnostics/agent_debug_log.dart';
import '../../settings/data/split_tunnel_prefs.dart';
import 'vpn_config.dart';
import 'vpn_route_policy.dart';
import 'vpn_service_config.dart';
import 'vpn_session_inputs.dart';
import 'vpn_session_meta.dart';
import 'xray_config_builder.dart';
import 'youtube_google_cidrs.dart';

/// Bridge between Flutter UI and Android VpnService (Xray / TrustTunnel).
///
/// Uses [MethodChannel] `teremok/vpn` for commands and [EventChannel]
/// `teremok/vpn/status` for live status updates from native code.
class VpnController {
  VpnController._();
  static final VpnController instance = VpnController._();

  static const _methodChannel = MethodChannel('teremok/vpn');
  static const _eventChannel = EventChannel('teremok/vpn/status');
  static const _trafficEventChannel = EventChannel('teremok/vpn/traffic');
  static const _pingEventChannel = EventChannel('teremok/vpn/ping');

  /// Xray start can take longer than sing-box (asset load + Reality handshake).
  static const Duration startTimeout = Duration(seconds: 45);

  static const Duration stopTimeout = Duration(seconds: 5);

  Stream<VpnNativeStatus>? _statusStream;
  Stream<VpnTrafficStats>? _trafficStream;
  Stream<int?>? _pingStream;

  /// Start Xray VPN with [VpnConfig.xrayProfile] candidates (sequential failover).
  Future<bool> start(VpnConfig config, {String? displayLabel}) async {
    try {
      if (config.xrayProfile.candidates.isEmpty) {
        throw VpnControllerException('xray_profile has no candidates');
      }

      final serviceConfig = VpnServiceConfig.fromVpnConfig(
        config,
        displayLabel: displayLabel,
      );
      // Always smart-style directs (Modes UI removed). Gated by prefs toggles.
      final bundledRu =
          kSmartRuSplitEnabled && await SplitTunnelPrefs.isBundledRuEnabled();
      final govRu =
          kSmartRuSplitEnabled && await SplitTunnelPrefs.isGovRuEnabled();
      final siteSuffixes = await SplitTunnelPrefs.enabledDomainSuffixes();
      final siteCidrs = await SplitTunnelPrefs.enabledProxyIpCidrs();
      final disallowedApps =
          (await SplitTunnelPrefs.loadDisallowedPackages()).toList()..sort();
      var ytCidrs = const <String>[];
      try {
        ytCidrs = await loadYoutubeGoogleCidrs();
      } catch (e) {
        // ignore: avoid_print
        print('[VPN] youtube-google.cidr skipped: $e');
      }

      await VpnSessionMeta.saveConnectMeta(
        ruRulesLoaded: bundledRu,
        ruRuleTags: const [],
        expectedEgressHost: config.expectedEgressHost,
      );

      final inputs = VpnSessionInputs.fromVpnConfig(
        config: config,
        service: serviceConfig,
        route: RoutePolicy(
          includeAdsBlock: kXrayAdsBlockEnabled,
          includeOgonAdsAll: kXrayOgonAdsAllEnabled,
          includeGeoipRu: kGeoipRuEnabled,
          includeBundledRuRuleSets: bundledRu,
          includeGovRuRuleSets: govRu,
          useHevTunBridge: kUseHevTunBridge,
          adsBlockDomains: kXrayAdsBlockDomains,
          proxyIpCidrs: ytCidrs,
          directDomainSuffixes: siteSuffixes,
          directIpCidrs: siteCidrs,
        ),
      );
      final candidates = XrayConfigBuilder.buildCandidateConfigs(inputs);
      final paramsJson = serviceConfig.toJsonStringWithXrayCandidates(
        candidates,
        disallowedApplications: disallowedApps,
      );

      final result = await _methodChannel
          .invokeMethod<bool>('start', {'paramsJson': paramsJson})
          .timeout(
            startTimeout,
            onTimeout: () {
              throw VpnControllerException(
                'start timeout after ${startTimeout.inSeconds}s',
              );
            },
          );
      if (result == true) {
        await SplitTunnelPrefs.markApplied();
      }
      return result ?? false;
    } on TimeoutException catch (e) {
      throw VpnControllerException('start timeout: $e');
    } on PlatformException catch (e) {
      throw VpnControllerException('start failed: ${e.code} ${e.message}');
    }
  }

  /// Start TrustTunnel core (ADR 006 dual-core).
  Future<bool> startTrustTunnel(
    TrustTunnelProfile profile, {
    String? displayLabel,
  }) async {
    try {
      final disallowedApps =
          (await SplitTunnelPrefs.loadDisallowedPackages()).toList()..sort();
      final paramsJson = jsonEncode({
        'schemaVersion': 2,
        'vpnCore': 'trusttunnel',
        'sessionName': kVpnBrandSessionName,
        'displayLabel': (displayLabel?.trim().isNotEmpty == true)
            ? displayLabel!.trim()
            : 'TrustTunnel · ${profile.hostname}',
        'outboundType': 'trusttunnel',
        'trusttunnelToml': profile.toml,
        'trusttunnelHost': profile.hostname,
        'trusttunnelNodeId': profile.nodeId,
        'controlPlaneHosts': VpnServiceConfig.controlPlaneHostsOf(),
        if (disallowedApps.isNotEmpty)
          'disallowedApplications': disallowedApps,
      });

      await agentDebugLog(
        hypothesisId: 'TT1',
        location: 'vpn_controller.dart:startTrustTunnel',
        message: 'tt start enqueued',
        runId: 'trusttunnel',
        data: {
          'nodeId': profile.nodeId,
          'host': profile.hostname,
          'upstream': profile.upstreamProtocol,
          'fallback': profile.upstreamFallbackProtocol,
          'antiDpi': profile.antiDpi,
          'dnsUpstreams': profile.dnsUpstreams.length,
          'tomlLen': profile.toml.length,
        },
      );

      final result = await _methodChannel
          .invokeMethod<bool>('start', {'paramsJson': paramsJson})
          .timeout(
            startTimeout,
            onTimeout: () {
              throw VpnControllerException(
                'start timeout after ${startTimeout.inSeconds}s',
              );
            },
          );
      if (result == true) {
        await SplitTunnelPrefs.markApplied();
      }
      return result ?? false;
    } on TimeoutException catch (e) {
      throw VpnControllerException('trusttunnel start timeout: $e');
    } on PlatformException catch (e) {
      throw VpnControllerException(
        'trusttunnel start failed: ${e.code} ${e.message}',
      );
    }
  }

  Future<bool> stop() async {
    try {
      final result = await _methodChannel
          .invokeMethod<bool>('stop')
          .timeout(
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

  Future<VpnNativeStatus> getStatus() async {
    try {
      final result = await _methodChannel.invokeMethod<String>('getStatus');
      return VpnNativeStatus.values.firstWhere(
        (s) => s.name == result,
        orElse: () => VpnNativeStatus.unknown,
      );
    } on PlatformException {
      return VpnNativeStatus.unknown;
    }
  }

  Future<bool> hasActiveSession() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('hasActiveSession');
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
  Future<String?> getVpnCoreStderrTail({int maxLines = 30}) async {
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
  Future<String?> getSingBoxStderrTail({int maxLines = 30}) =>
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
      final result =
          await _methodChannel.invokeMethod<bool>('openVpnSettings');
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Detect Always-on VPN held by another app (Android only).
  Future<VpnConflictInfo> queryVpnConflict() async {
    try {
      final raw =
          await _methodChannel.invokeMethod<dynamic>('getVpnConflict');
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
    _statusStream ??= _eventChannel
        .receiveBroadcastStream()
        .map((event) {
          if (event is String) {
            return VpnNativeStatus.values.firstWhere(
              (s) => s.name == event,
              orElse: () => VpnNativeStatus.unknown,
            );
          }
          return VpnNativeStatus.unknown;
        })
        .handleError((_) {
          return VpnNativeStatus.unknown;
        });
    return _statusStream!;
  }

  Stream<VpnTrafficStats> get trafficStream {
    _trafficStream ??= _trafficEventChannel
        .receiveBroadcastStream()
        .map((event) {
          if (event is Map) {
            final down = event['downlinkBps'];
            final up = event['uplinkBps'];
            return VpnTrafficStats(
              downlinkBps: (down is num) ? down.toInt() : 0,
              uplinkBps: (up is num) ? up.toInt() : 0,
            );
          }
          return const VpnTrafficStats.zero();
        })
        .handleError((_) => const VpnTrafficStats.zero());
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

/// Snapshot from Android `getVpnConflict` (foreign Always-on holder).
final class VpnConflictInfo {
  const VpnConflictInfo({
    required this.foreignAlwaysOn,
    this.packageName,
    this.appLabel,
    this.lockdown,
  });

  static const none = VpnConflictInfo(foreignAlwaysOn: false);

  final bool foreignAlwaysOn;
  final String? packageName;
  final String? appLabel;
  final bool? lockdown;

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
    final lockdownRaw = map['lockdown'];
    final lockdown = lockdownRaw is bool ? lockdownRaw : null;
    // Android 12+ may hide always_on_vpn_app while lockdown=1 is still visible.
    // Treat lockdown-without-readable-pkg as a blocking conflict for UX.
    final blocking = foreign || lockdown == true;
    if (!blocking) return VpnConflictInfo.none;
    return VpnConflictInfo(
      foreignAlwaysOn: true,
      packageName: map['packageName']?.toString(),
      appLabel: map['appLabel']?.toString(),
      lockdown: lockdown,
    );
  }
}

