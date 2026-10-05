import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../settings/data/installed_apps_channel.dart';
import '../../settings/data/split_tunnel_prefs.dart';
import '../../../core/ios_store_gates.dart';
import 'vpn_config.dart';
import 'vpn_route_policy.dart';
import 'vpn_service_config.dart';
import 'vpn_session_snapshot.dart';
import 'windows_tunnel.dart';

bool get _isIosSplit => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
bool get _isAndroidNative =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Bridge between Flutter UI and Android VpnService (Hysteria2, ADR 018).
///
/// Uses [MethodChannel] `proxydom/vpn` for commands and [EventChannel]
/// `proxydom/vpn/status` for live status updates from native code.
class VpnController {
  VpnController._();
  static final VpnController instance = VpnController._();

  static const _methodChannel = MethodChannel('proxydom/vpn');
  static const _eventChannel = EventChannel('proxydom/vpn/status');
  static const _sessionEventChannel = EventChannel('proxydom/vpn/session');
  static const _trafficEventChannel = EventChannel('proxydom/vpn/traffic');
  static const _pingEventChannel = EventChannel('proxydom/vpn/ping');

  static const Duration stopTimeout = Duration(seconds: 5);

  Stream<VpnNativeStatus>? _statusStream;
  Stream<VpnSessionSnapshot>? _sessionStream;
  Stream<VpnTrafficStats>? _trafficStream;
  Stream<int?>? _pingStream;
  String? windowsNotice;
  String? windowsCode;
  bool windowsAccepted = false;
  int windowsGeneration = 0;

  bool get windowsNestLocked => WindowsTunnel.instance.nestLocked;

  /// Pipe closed or the controller binary is missing. Not a live connect.
  bool get windowsBrokerCooling => WindowsTunnel.instance.brokerCooling;

  /// One share line through the Windows broker (ADR 031).
  ///
  /// Games reach their servers over UDP to bare addresses that change, so no
  /// domain rule can keep them off the tunnel and no IP list survives a patch.
  /// Windows therefore bypasses UDP by protocol, and the force-proxy hosts are
  /// sent separately so their QUIC does not leave through that same rule.
  Future<bool> startWindowsShare(String uri) async {
    final domains = stripForceProxySuffixes(
      await SplitTunnelPrefs.enabledDomainSuffixes(),
    );
    final result = await WindowsTunnel.instance.connect(
      uri,
      directDomains: domains,
      forceProxyDomains: kSmartProxyForceSuffixes,
      udpDirect: true,
    );
    windowsNotice = result.notice;
    windowsCode = result.code;
    windowsAccepted = result.accepted;
    windowsGeneration = result.generation;
    return result.ok;
  }

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
    if (!_isIosSplit) {
      try {
        final apps = await InstalledAppsChannel.listLauncherApps(
          includeIcons: false,
        );
        if (apps.isNotEmpty) {
          // Empty list would still set one-shot seed flags and skip later
          // Home/connect once the plugin is ready.
          await SplitTunnelPrefs.seedDefaultBypassIfNeeded(
            apps.map((a) => a.packageName),
          );
        }
      } catch (_) {}
    }
    final disallowedApps = _isIosSplit
        ? const <String>[]
        : ((await SplitTunnelPrefs.loadDisallowedPackages()).toList()..sort());
    if (_isIosSplit) {
      await SplitTunnelPrefs.ensureIosSitesAllEnabledIfNeeded();
    }
    final directSuffixes = _isIosSplit
        ? const <String>[]
        : stripForceProxySuffixes(
            await SplitTunnelPrefs.enabledDomainSuffixes(),
          );
    final iosCustomHosts = !_isIosSplit
        ? const <String>[]
        : stripForceProxySuffixes(
            await SplitTunnelPrefs.enabledIosCustomResolutionHosts(),
          );
    final iosCatalogHosts = !_isIosSplit
        ? const <String>[]
        : stripForceProxySuffixes(
            await SplitTunnelPrefs.enabledIosCatalogResolutionHosts(),
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
      // Android: Go hyDialer suffixes. iOS: prioritized OS routes only.
      if (directSuffixes.isNotEmpty) 'directDomainSuffixes': directSuffixes,
      if (iosCustomHosts.isNotEmpty) 'iosCustomResolutionHosts': iosCustomHosts,
      if (iosCatalogHosts.isNotEmpty)
        'iosCatalogResolutionHosts': iosCatalogHosts,
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
  Future<bool> startAuto(List<String> paramsJsonList, {String? sessionId}) async {
    if (paramsJsonList.isEmpty) {
      throw VpnControllerException('auto pool empty');
    }
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        'startAuto',
        {'candidatesJson': paramsJsonList, if (sessionId != null) 'sessionId': sessionId},
      );
      return result ?? false;
    } on PlatformException catch (e) {
      throw VpnControllerException('auto start failed: ${e.code} ${e.message}');
    }
  }

  /// Start Hysteria2 core (ADR 015). Native proves via local SOCKS, not QUIC-up.
  ///
  /// [sessionId] is the ShareSessionLog id for this attempt. The native layer
  /// stamps it on every line so a report can be read as one timeline instead of
  /// a Dart phase log next to an unrelated Android logcat.
  Future<bool> startHysteria(
    HysteriaProfile profile, {
    String? displayLabel,
    String? sessionId,
  }) async {
    try {
      final disallowedApps = _isIosSplit
          ? const <String>[]
          : ((await SplitTunnelPrefs.loadDisallowedPackages()).toList()
            ..sort());
      final directSuffixes = _isIosSplit
          ? const <String>[]
          : stripForceProxySuffixes(
              await SplitTunnelPrefs.enabledDomainSuffixes(),
            );
      final iosCustomHosts = !_isIosSplit
          ? const <String>[]
          : stripForceProxySuffixes(
              await SplitTunnelPrefs.enabledIosCustomResolutionHosts(),
            );
      final iosCatalogHosts = !_isIosSplit
          ? const <String>[]
          : stripForceProxySuffixes(
              await SplitTunnelPrefs.enabledIosCatalogResolutionHosts(),
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
        if (profile.insecure) 'hysteriaInsecure': true,
        if (profile.obfs.isNotEmpty) 'hysteriaObfs': profile.obfs,
        if (profile.obfsPassword.isNotEmpty)
          'hysteriaObfsPassword': profile.obfsPassword,
        'controlPlaneHosts': VpnServiceConfig.controlPlaneHostsOf(),
        if (disallowedApps.isNotEmpty) 'disallowedApplications': disallowedApps,
        if (directSuffixes.isNotEmpty) 'directDomainSuffixes': directSuffixes,
        if (iosCustomHosts.isNotEmpty)
          'iosCustomResolutionHosts': iosCustomHosts,
        if (iosCatalogHosts.isNotEmpty)
          'iosCatalogResolutionHosts': iosCatalogHosts,
      });

      final result = await _methodChannel.invokeMethod<bool>(
        'start',
        {
          'paramsJson': paramsJson,
          if (sessionId != null) 'sessionId': sessionId,
        },
      );
      return result ?? false;
    } on PlatformException catch (e) {
      throw VpnControllerException(
        'hysteria start failed: ${e.code} ${e.message}',
      );
    }
  }

  /// Start in-process Xray (same gomobile runtime as Hy2). [configJson] has
  /// secrets; it is not logged.
  ///
  /// Android app exclusions use the same package list as Hysteria2. Site
  /// suffixes stay out of this start: VLESS does not apply them, and
  /// [SplitTunnelPrefs.markApplied] would hide that the site draft is still
  /// pending.
  Future<bool> startXray(
    String configJson, {
    String? displayLabel,
    String? sessionId,
  }) async {
    try {
      final disallowedApps = _isIosSplit
          ? const <String>[]
          : ((await SplitTunnelPrefs.loadDisallowedPackages()).toList()
            ..sort());
      final paramsJson = jsonEncode({
        'schemaVersion': 2,
        'vpnCore': 'xray',
        'sessionName': kVpnBrandSessionName,
        'displayLabel': (displayLabel?.trim().isNotEmpty == true)
            ? displayLabel!.trim()
            : kVpnBrandSessionName,
        'outboundType': 'xray',
        'xrayConfig': configJson,
        if (disallowedApps.isNotEmpty) 'disallowedApplications': disallowedApps,
      });
      final result = await _methodChannel.invokeMethod<bool>(
        'start',
        {
          'paramsJson': paramsJson,
          if (sessionId != null) 'sessionId': sessionId,
        },
      );
      return result ?? false;
    } on PlatformException catch (e) {
      throw VpnControllerException('xray start failed: ${e.code}');
    }
  }

  Future<String?> getLastError() async {
    try {
      return await _methodChannel.invokeMethod<String>('getLastError');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<String?> getShareTcp() async {
    try {
      return await _methodChannel.invokeMethod<String>('getShareTcp');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// True only after native leaves preparing/connecting. [start] itself returns
  /// when the service accepts the command, before the worker finishes.
  Future<bool> waitUntilSessionSettled() async {
    final deadline = DateTime.now().add(const Duration(seconds: 25));
    var sawBusy = false;
    while (DateTime.now().isBefore(deadline)) {
      final status = await getStatus();
      if (status == VpnNativeStatus.connecting ||
          status == VpnNativeStatus.preparing ||
          status == VpnNativeStatus.connected) {
        sawBusy = true;
      }
      if (sawBusy && status == VpnNativeStatus.connected) return true;
      if (sawBusy &&
          (status == VpnNativeStatus.error || status == VpnNativeStatus.idle)) {
        return false;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return false;
  }

  /// True only where the native side answers `getProvenEgress`.
  ///
  /// [provenEgressIp] returns null when the channel has no case for the method,
  /// and null used to be read as "no egress", so the post-connect probe tore
  /// down live sessions on iOS and Windows. Those platforms prove the tunnel in
  /// their own layer — the iOS OS route set and the Windows broker gate.
  bool get egressProbeSupported => _isAndroidNative;

  Future<String?> provenEgressIp() async {
    try {
      return await _methodChannel.invokeMethod<String>('getProvenEgress');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<bool> stop({String reason = 'user_tap'}) async {
    if (windowsDesktop) {
      final restored = await WindowsTunnel.instance.disconnect();
      windowsNotice = WindowsTunnel.instance.notice;
      return restored;
    }
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        'stop',
        {'reason': reason},
      ).timeout(
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
  Future<bool> wipeSession({String reason = 'logout'}) async {
    if (windowsDesktop) return stop(reason: reason);
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        'wipeSession',
        {'reason': reason},
      );
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Live or persisted Packet Tunnel health JSON (iOS); null elsewhere.
  Future<String?> getTunnelHealth() async {
    try {
      return await _methodChannel.invokeMethod<String>('getTunnelHealth');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<VpnNativeStatus> getStatus() async {
    if (windowsDesktop) {
      return switch (WindowsTunnel.instance.phase) {
        'connecting' => VpnNativeStatus.connecting,
        'connected' => VpnNativeStatus.connected,
        'disconnecting' => VpnNativeStatus.disconnecting,
        _ => VpnNativeStatus.idle,
      };
    }
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
    if (windowsDesktop) {
      final phase = WindowsTunnel.instance.phase;
      return phase == 'connected' || phase == 'connecting';
    }
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

  /// Core decision log level. Applied on the next Xray start.
  Future<void> setCoreLogLevel(String level) async {
    try {
      await _methodChannel.invokeMethod<void>(
        'setCoreLogLevel',
        {'level': level},
      );
    } on PlatformException {
      return;
    } on MissingPluginException {
      return;
    }
  }

  /// Drop the on-disk core windows. The in-memory product ring is separate.
  Future<void> clearCoreLog() async {
    try {
      await _methodChannel.invokeMethod<void>('clearCoreLog');
    } on PlatformException {
      return;
    } on MissingPluginException {
      return;
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

  /// iOS App Group ring (Runner + Packet Tunnel). Android → null.
  Future<String?> getNativeLogTail() async {
    try {
      return await _methodChannel.invokeMethod<String>('getNativeLogTail');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

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

  /// Opens the system battery exemption screen. Does not promise the grant.
  Future<bool> requestBatteryExemption() async {
    try {
      final result =
          await _methodChannel.invokeMethod<bool>('requestBatteryExemption');
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

/// Parses EventChannel `proxydom/vpn/ping` payloads.
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
