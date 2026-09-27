import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/diagnostics/product_log.dart';
import '../../../core/diagnostics/session_trace.dart';
import '../../../core/ios_store_gates.dart';
import '../../vpn/data/hy2_import_store.dart';
import '../../vpn/data/route_document.dart';
import '../../vpn/data/share_session_log.dart';
import '../../vpn/data/subscription_device.dart';
import '../../vpn/data/subscription_label.dart';
import '../../vpn/data/vpn_config.dart';
import '../../vpn/data/vpn_controller.dart';
import '../../vpn/data/vpn_nodes_repository.dart';
import '../../vpn/data/vpn_service_config.dart';
import '../../vpn/data/vpn_session_meta.dart';
import '../../vpn/data/vpn_session_snapshot.dart';
import '../../vpn/data/xray_share_config.dart';
import '../../vpn/domain/vpn_connect_error.dart';
import '../../settings/data/auto_reconnect_prefs.dart';
import '../../settings/data/split_tunnel_prefs.dart';
import 'vpn_status.dart';
import 'vpn_status_log.dart';

final vpnNodesRepositoryProvider = Provider<VpnNodesRepository>(
  (ref) => VpnNodesRepository(),
);

const _connectedSinceKey = 'vpn_connected_since_ms';

/// Home + analytics: another VPN / Always-on / lockdown is blocking.
const kVpnConflictErrorCode = 'vpn_conflict';

/// Connecting UI hung without a real foreign-VPN conflict (iOS hot-switch race).
const kVpnConnectTimeoutErrorCode = 'connect_timeout';

/// Hot region switch: mint while TUN up, then tear down, then reconnect.
///
/// Order matters — mint after stop times out on iOS RF without tunnel (~18s).
@visibleForTesting
Future<void> runHotRegionSwitch({
  required Future<void> Function() mint,
  required Future<void> Function() stopAndWaitIdle,
  required Future<void> Function() connectReuse,
}) async {
  await mint();
  await stopAndWaitIdle();
  await connectReuse();
}

/// VPN-контроллер. Шаг 16: retry/reconnect логика поверх VpnController + native.
class VpnNotifier extends Notifier<VpnStatus> {
  VpnConfig? _config;

  /// Label from catalog after Auto/manual pick (overrides generic host fallback).
  String? _displayLabel;
  String? _sid;
  Map<String, Object?> _sessionFields = const {};
  String? _profileHost;
  bool _freeSessionOpen = false;
  String? _freeSessionKey;

  /// Scheme of the selected local line (`hysteria2`, `vless`, …).
  String? _selectedNodeProtocol;

  String? _autoActiveNodeId;

  /// Последний полученный конфиг. Доступен из UI для preview.
  VpnConfig? get config => _config;

  /// Friendly region label for the active egress hop (read-only Home card).
  String? get displayLabel => _displayLabel;

  /// Auto prove winner catalog id (null when not Auto / not yet proved).
  String? get autoWinnerId => _autoActiveNodeId;

  /// Last prove snapshot for owner reports (id + outcome, no secrets).
  String? get lastProveSummary => _lastProveSummary;

  String? get catalogHost => _catalogHost;

  String? _lastProveSummary;
  String? _lastLoggedProveId;
  String? _catalogHost;

  /// Session Binding/Proving/TunUp/CoreStarting owns error/idle until terminal.
  bool _sessionOwnsUi = false;

  /// SOCKS prove only — Binding+TUN must still paint Connected from native.
  bool _sessionProving = false;

  /// User tap Auto/connect until ConnectedHealthy / Error / disconnect.
  /// Native hop idle must not paint Nest rest in this window.
  bool _sessionWalkActive = false;

  VpnSessionPhase _lastSessionPhase = VpnSessionPhase.unknown;

  /// Bumped on each [connect] and [disconnect]. In-flight `_connectBody`
  /// must not paint Nest Connected after a newer Nest stop.
  int _connectGeneration = 0;

  /// Generation captured by the in-flight [connect] (null when idle).
  int? _activeConnectGen;

  int get connectGeneration => _connectGeneration;

  void _beginSessionWalk() {
    _sessionWalkActive = true;
  }

  void _endSessionWalk() {
    _sessionWalkActive = false;
  }

  bool _shouldDropConnectingOnIdle() {
    if (state is! VpnConnecting) return false;
    if (_wifiRetryPending) return false;
    return connectingIdleShouldDrop(
      walkActive: _sessionWalkActive,
      sessionOwnsUi: _sessionOwnsUi,
      lastPhase: _lastSessionPhase,
      userStopping: _suppressAutoReconnect,
    );
  }

  bool _isConnectStale(int gen) => gen != _connectGeneration;

  bool _idleMustNotDemote() {
    if (_wifiRetryPending) return true;
    return nativeIdleMustNotDemote(
      walkActive: _sessionWalkActive,
      sessionOwnsUi: _sessionOwnsUi,
      lastPhase: _lastSessionPhase,
      userStopping: _suppressAutoReconnect,
      uiConnected: state is VpnConnected,
      nativeSyncComplete: _nativeSyncComplete,
    );
  }

  Future<String?> _selectedHost() async {
    final imported = await Hy2ImportStore.instance.selected();
    final endpoint = imported?.endpoint.trim();
    if (endpoint == null || endpoint.isEmpty) return null;
    return endpoint;
  }

  /// startHysteria returns when the service is queued, not when Hy2 finishes.
  /// Hold this connect until native leaves preparing/connecting so a second
  /// tap cannot enqueue another start.
  Future<void> _waitUntilHandshakeSettles(int gen) async {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(deadline)) {
      if (await _abortStaleConnect(gen)) return;
      final native = await VpnController.instance.getStatus();
      if (native != VpnNativeStatus.connecting &&
          native != VpnNativeStatus.preparing &&
          native != VpnNativeStatus.disconnecting) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }

  Future<bool> _abortStaleConnect(int gen) async {
    if (!_isConnectStale(gen)) return false;
    ShareSessionLog.emit(
      'vpn.connect_abort',
      level: ProductLogLevel.debug,
      sid: _sid,
      extra: {'gen': gen, 'now': _connectGeneration},
    );
    _endSessionWalk();
    _cancelConnectingWatchdog();
    if (_suppressAutoReconnect &&
        (state is VpnConnecting || state is VpnConnected)) {
      _lastSessionPhase = VpnSessionPhase.idle;
      state = const VpnDisconnected();
      await VpnController.instance.stop(reason: 'stale_connect');
    }
    return true;
  }

  /// After restore teardown: wait until native is idle so Home can paint rest.
  /// Returns false if still Stopping/Connected after [timeout].
  Future<bool> waitUntilNativeIdle({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final native = await VpnController.instance.getStatus();
      if (native == VpnNativeStatus.idle ||
          native == VpnNativeStatus.unknown ||
          native == VpnNativeStatus.error) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    return false;
  }

  StreamSubscription<VpnNativeStatus>? _statusSubscription;
  StreamSubscription<VpnSessionSnapshot>? _sessionSubscription;
  Timer? _reconnectTimer;
  Timer? _connectingPoll;
  Timer? _disconnectWatchdog;
  Future<void>? _syncInFlight;
  final NativeStatusLog _nativeStatusLog = NativeStatusLog();
  DateTime? _connectingUiStartedAt;

  /// Cold-start getStatus loop finished — ignore idle demotion until then.
  bool _nativeSyncComplete = false;

  /// Single-flight Connected paint + egress probe per generation.
  int? _enterConnectedGenInFlight;
  int _egressProbeToken = 0;

  /// UI Connecting without native Connected — then conflict CTA, not a spinner.
  static const stuckConnectingTimeout = Duration(seconds: 18);

  /// True while a connect() Future is in-flight (dedupe concurrent callers).
  Future<void>? _connectInFlight;
  bool _autoReconnectArmed = false;

  /// Set after intentional stop / self-revoke — blocks [_scheduleReconnect]
  /// and syncFromNative auto-reconnect until the next user [connect].
  bool _suppressAutoReconnect = false;

  /// True while a server switch is waiting for the previous tunnel to go idle.
  bool _switchStop = false;
  int _dialGen = 0;
  int _liveDialGen = 0;
  int _nativeGenFloor = 0;
  int _lastNativeGen = 0;
  String? _handshakeHost;

  /// One PathIncompatible Auto retry on Wi-Fi (issue #147).
  bool _wifiAutoRetryUsed = false;
  bool _wifiRetryPending = false;
  Timer? _wifiRetryTimer;
  int _autoConnectAttempt = 1;

  void _cancelWifiRetry() {
    _wifiRetryTimer?.cancel();
    _wifiRetryTimer = null;
    _wifiRetryPending = false;
  }

  void _cancelConnectingWatchdog() {
    _connectingPoll?.cancel();
    _connectingPoll = null;
    _connectingUiStartedAt = null;
  }

  void _cancelDisconnectWatchdog() {
    _disconnectWatchdog?.cancel();
    _disconnectWatchdog = null;
  }

  /// Align UI with native without auto-reconnect side effects.
  ///
  /// Fixes stuck Nest `VpnConnecting` when the tunnel is already up (foreign VPN
  /// churn / hung `stop` / missed EventChannel).
  Future<void> reconcileWithNative() async {
    final native = await VpnController.instance.getStatus();
    final before = vpnUiPhase(state);
    switch (native) {
      case VpnNativeStatus.connected:
        if (state is VpnConnected) return;
        if (!shouldApplyNativeConnected(
          ui: state,
          sessionProving: _sessionProving,
        )) {
          return;
        }
        await _enterConnected(freshSession: state is VpnConnecting);
        _logReconcile(native, before);
      case VpnNativeStatus.connecting:
      case VpnNativeStatus.preparing:
        if (_sessionOwnsUi) return;
        if (state is VpnDisconnected || state is VpnError) {
          state = const VpnConnecting(progress: 0.5);
          _armConnectingPoll();
          _logReconcile(native, before);
        }
      case VpnNativeStatus.idle:
      case VpnNativeStatus.unknown:
        if (_sessionWalkActive || _sessionOwnsUi) return;
        if (_idleMustNotDemote()) {
          return;
        }
        if (state is VpnConnecting && _connectInFlight == null) {
          await _failConnectingIdle();
          _logReconcile(native, before);
        } else if (state is VpnConnected) {
          await _confirmIdleDrop();
          _logReconcile(native, before);
        }
      case VpnNativeStatus.error:
        if (_sessionOwnsUi) return;
        if (state is! VpnError) {
          state = await _vpnErrorFromNative();
          _logReconcile(native, before);
        }
      case VpnNativeStatus.disconnecting:
        break;
      case VpnNativeStatus.revoked:
        _endSessionWalk();
        if (state is VpnConnected || state is VpnConnecting) {
          await _clearConnectedSince();
          state = const VpnError(message: 'VPN was revoked by system');
          ProductLog.event(
            'vpn.connect_fail',
            level: ProductLogLevel.error,
            fields: {'code': 'revoked'},
          );
          _logReconcile(native, before);
        }
    }
  }

  void _logReconcile(VpnNativeStatus native, String before) {
    final after = vpnUiPhase(state);
    if (after == before) return;
    _vpnLog('vpn.reconcile native=${native.name} from=$before to=$after');
  }

  void _logNativeStatus(VpnNativeStatus status) {
    final line = _nativeStatusLog.lineFor(status);
    if (line == null) return;
    _vpnLog(line);
  }

  bool _coreStartLogged = false;

  void _logCoreStart({required bool ok}) {
    if (_sid == null || _coreStartLogged) return;
    _coreStartLogged = true;
    if (ok) {
      ShareSessionLog.emit(
        'vpn.core_start',
        level: ProductLogLevel.info,
        sid: _sid,
        extra: {'ok': true},
      );
      unawaited(_logShareTcp());
      return;
    }
    unawaited(VpnController.instance.getLastError().then((detail) {
      ShareSessionLog.emit(
        'vpn.core_start',
        level: ProductLogLevel.error,
        sid: _sid,
        extra: {'ok': false, 'error': detail},
      );
    }));
    unawaited(_logShareTcp());
  }

  Future<void> _logShareTcp() async {
    final detail = await VpnController.instance.getShareTcp();
    if (detail == null || detail.trim().isEmpty) return;
    ShareSessionLog.emit(
      'vpn.server_tcp',
      level: ProductLogLevel.debug,
      sid: _sid,
      extra: {'detail': detail},
    );
  }

  /// Poll native while UI is connecting. Never force-stops (ADR 014 / 015).
  void _armConnectingPoll() {
    _cancelConnectingWatchdog();
    _connectingUiStartedAt = DateTime.now();
    _connectingPoll = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      unawaited(_pollConnectingNative());
    });
  }

  Future<void> _pollConnectingNative() async {
    if (state is! VpnConnecting) {
      _connectingPoll?.cancel();
      _connectingPoll = null;
      return;
    }
    if (_sessionProving) return;
    final native = await VpnController.instance.getStatus();
    if (native == VpnNativeStatus.connected) {
      _logCoreStart(ok: true);
      await _enterConnected(freshSession: true);
      return;
    }
    if (native == VpnNativeStatus.error) {
      _logCoreStart(ok: false);
      await _failConnectingFromNative();
      return;
    }
    final startedAt = _connectingUiStartedAt;
    if (startedAt != null &&
        DateTime.now().difference(startedAt) >= stuckConnectingTimeout) {
      await _failConnectingStuck();
      return;
    }
    if (_sessionWalkActive) return;
    if (native == VpnNativeStatus.idle && _connectInFlight == null) {
      if (_idleMustNotDemote()) {
        return;
      }
      await _failConnectingIdle();
    }
  }

  Future<VpnError> _vpnErrorFromConflict(VpnConflictInfo conflict) {
    final label = conflict.appLabel?.trim();
    return Future.value(
      VpnError(
        message: (label != null && label.isNotEmpty) ? label : 'vpn_conflict',
        code: kVpnConflictErrorCode,
      ),
    );
  }

  Future<VpnError> _vpnErrorFromNative({
    String fallbackMessage = 'Native VPN error',
  }) async {
    final detail = await VpnController.instance.getLastError();
    return vpnErrorFromNativeDetail(
      detail,
      fallbackMessage: fallbackMessage,
    );
  }

  /// After prepare denial: foreign Always-on / live VPN → [vpn_conflict], else permission.
  Future<VpnError> _errorForPermissionFailure() async {
    final conflict = await VpnController.instance.queryVpnConflict();
    if (conflict.foreignAlwaysOn) {
      return _vpnErrorFromConflict(conflict);
    }
    return const VpnError(
      message: 'VPN permission denied',
      code: 'permission_denied',
    );
  }

  /// When [VpnController.start] returns false — often establish blocked by another VPN.
  Future<VpnError> _errorForStartFailure() async {
    final conflict = await VpnController.instance.queryVpnConflict();
    if (conflict.foreignAlwaysOn) {
      return _vpnErrorFromConflict(conflict);
    }
    final detail = await VpnController.instance.getLastError();
    if (detail != null && detail.toLowerCase().contains('permission denied')) {
      return _errorForPermissionFailure();
    }
    return await _vpnErrorFromNative(
      fallbackMessage: 'Failed to start VPN service',
    );
  }

  /// Keep uptime across UI restarts while the same VpnService session lives.
  Future<DateTime> _resolveConnectedSince({required bool freshSession}) async {
    final prefs = await SharedPreferences.getInstance();
    if (!freshSession) {
      final ms = prefs.getInt(_connectedSinceKey);
      if (ms != null && ms > 0) {
        return DateTime.fromMillisecondsSinceEpoch(ms);
      }
    }
    final now = DateTime.now();
    await prefs.setInt(_connectedSinceKey, now.millisecondsSinceEpoch);
    return now;
  }

  Future<void> _clearConnectedSince() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_connectedSinceKey);
    await VpnSessionMeta.clear();
  }

  Future<void> _enterConnected({required bool freshSession, int? gen}) async {
    // Auto SOCKS prove: session snapshot is SoT. Binding+TUN in the shade
    // must still paint Nest Connected (ConnectedHealthy can lag / miss).
    if (_sessionProving) return;
    if (_suppressAutoReconnect || _switchStop) return;
    if (hideInAppPlategaCheckout && _liveDialGen != _dialGen) return;
    final effectiveGen = gen ?? _activeConnectGen ?? _connectGeneration;
    if (_enterConnectedGenInFlight == effectiveGen) {
      return;
    }
    _enterConnectedGenInFlight = effectiveGen;
    try {
      await _enterConnectedBody(freshSession: freshSession, gen: gen);
    } finally {
      if (_enterConnectedGenInFlight == effectiveGen) {
        _enterConnectedGenInFlight = null;
      }
    }
  }

  Future<void> _enterConnectedBody({
    required bool freshSession,
    int? gen,
  }) async {
    final native = await VpnController.instance.getStatus();
    if (shouldRefuseEnterConnected(
      sessionProving: _sessionProving,
      connectGen: gen ?? _activeConnectGen,
      currentGen: _connectGeneration,
      walkActive: _sessionWalkActive,
      sessionOwnsUi: _sessionOwnsUi,
      nativeConnected: native == VpnNativeStatus.connected,
      userStopping: _suppressAutoReconnect,
    )) {
      _vpnLog(
        '[VPN] enter_connected refused native=$native '
        'gen=${gen ?? _activeConnectGen} now=$_connectGeneration '
        'walk=$_sessionWalkActive owns=$_sessionOwnsUi',
      );
      return;
    }
    // Seed phase before EventChannel can replay idle (cold-start race).
    if (_lastSessionPhase == VpnSessionPhase.unknown ||
        _lastSessionPhase == VpnSessionPhase.idle ||
        _lastSessionPhase == VpnSessionPhase.stopping) {
      _lastSessionPhase = VpnSessionPhase.connectedHealthy;
    }
    await _hydrateConnectedUi();
    final config = _config;
    final serverName = connectedServerName(
      config: config,
      displayLabel: _displayLabel,
    );
    final protocol = sessionProtocolLabel(
      config: config,
      selectedNodeProtocol: _selectedNodeProtocol,
    );
    final sessionKey = '${_sessionScheme(protocol)}|$_profileHost|$serverName';
    if (keepLiveFreeSession(
      freeClient: freeKeyClient,
      sessionOpen: _freeSessionOpen,
      sameProfile: _freeSessionKey == sessionKey,
    )) {
      _endSessionWalk();
      _cancelConnectingWatchdog();
      return;
    }
    if (state is VpnConnected && !freshSession) {
      final cur = state as VpnConnected;
      if (cur.serverName == serverName && cur.protocol == protocol) {
        _endSessionWalk();
        return;
      }
      _endSessionWalk();
      _cancelConnectingWatchdog();
      state = VpnConnected(
        serverName: serverName,
        protocol: protocol,
        connectedSince: cur.connectedSince,
      );
      _rememberFreeSession(sessionKey);
      unawaited(_persistConnectedUi());
      return;
    }
    final since = await _resolveConnectedSince(freshSession: freshSession);
    if (_sessionProving) return;
    if (gen != null && gen != _connectGeneration) return;
    final nativeAfter = await VpnController.instance.getStatus();
    if (shouldRefuseEnterConnected(
      sessionProving: _sessionProving,
      connectGen: gen ?? _activeConnectGen,
      currentGen: _connectGeneration,
      walkActive: _sessionWalkActive,
      sessionOwnsUi: _sessionOwnsUi,
      nativeConnected: nativeAfter == VpnNativeStatus.connected,
      userStopping: _suppressAutoReconnect,
    )) {
      return;
    }
    _endSessionWalk();
    _cancelConnectingWatchdog();
    state = VpnConnected(
      serverName: serverName,
      protocol: protocol,
      connectedSince: since,
    );
    SessionTrace.mark('connected');
    _rememberFreeSession(sessionKey);
    unawaited(_persistConnectedUi());
    final probeToken = ++_egressProbeToken;
    unawaited(_logEgressProbe(token: probeToken));
    unawaited(
      VpnController.instance.getUnderlyingNetworkInterface().then((iface) {
        final name = iface?.trim();
        if (name == null || name.isEmpty || name == _lastLoggedIface) return;
        _lastLoggedIface = name;
        ProductLog.event(
          'net.iface',
          level: ProductLogLevel.debug,
          fields: {'name': name},
        );
      }),
    );
  }

  Future<void> _hydrateConnectedUi() async {
    await _hydrateImportedProfileUi();
  }

  /// A free key client has no catalog session. The selected local profile owns
  /// user-facing identity; native owns only lifecycle.
  Future<void> _hydrateImportedProfileUi() async {
    _config = null;
    _autoActiveNodeId = null;
    _catalogHost = null;
    final imported = await Hy2ImportStore.instance.selected();
    _displayLabel = imported == null ? null : labelForShareLink(imported).title;
    _selectedNodeProtocol = imported?.scheme;
    _profileHost =
        imported == null ? null : profileHostForLog(imported.endpoint);
  }

  Future<void> _persistConnectedUi() async {
    try {
      // Import identity is restored from Hy2ImportStore, never from a catalog cache.
      await VpnSessionMeta.clear();
    } catch (_) {}
  }

  /// After TUN is up: icanhazip vs catalog IPv4 (not SNI / expected_egress_host).
  Future<void> _logEgressProbe({int? token}) async {
    final mine = token ?? _egressProbeToken;
    if (_suppressAutoReconnect ||
        _lastSessionPhase == VpnSessionPhase.stopping ||
        _lastSessionPhase == VpnSessionPhase.idle) {
      return;
    }
    try {
      _catalogHost = null;
      final ip = await VpnController.instance.provenEgressIp();
      if (mine != _egressProbeToken || state is! VpnConnected) return;
      final shownIp = ip?.trim() ?? '';
      final ok = shownIp.isNotEmpty;
      final error = ok ? null : await VpnController.instance.getLastError();
      ShareSessionLog.emit(
        'vpn.egress_probe',
        level: ok ? ProductLogLevel.info : ProductLogLevel.error,
        sid: _sid,
        extra: {
          'ok': ok,
          'external_ip': ok ? shownIp : 'fail',
          'phase': _lastSessionPhase.name,
          'error': error ?? (ok ? null : 'no egress ip'),
        },
      );
      if (!ok) {
        _lastSessionPhase = VpnSessionPhase.connectedDegraded;
        state = const VpnError(message: 'egress_fail', code: 'egress_fail');
        await VpnController.instance.stop(reason: 'egress_fail');
      }
    } catch (e) {
      ProductLog.event(
        'vpn.egress_probe',
        level: ProductLogLevel.error,
        fields: {'ok': false, 'error': e.runtimeType.toString()},
      );
      _vpnLog('[VPN] egress_probe failed: $e');
    }
  }

  @override
  VpnStatus build() {
    // Dispose: cancel timers/subs only — never MethodChannel stop.
    ref.onDispose(_disposeLocalOnly);
    // Always listen — EventChannel replays last native status on subscribe.
    _subscribeToStatus();
    // Dart UI restarts independently of VpnService — sync tray/native status.
    Future.microtask(_syncFromNative);
    return const VpnDisconnected();
  }

  /// True while [connect] is in-flight (dedupe + Nest cancel UX).
  bool get isConnectInFlight => _connectInFlight != null;

  /// Align UI with native VpnService after cold start / Activity recreate.
  Future<void> syncFromNative() => _syncFromNative();

  Future<void> _syncFromNative() {
    return _syncInFlight ??= _syncFromNativeBody().whenComplete(() {
      _syncInFlight = null;
    });
  }

  Future<void> _syncFromNativeBody() async {
    try {
      // Always-on restore races: service may briefly report preparing/idle.
      VpnNativeStatus? native;
      for (var attempt = 0; attempt < 5; attempt++) {
        native = await VpnController.instance.getStatus();
        _logNativeStatus(native);
        if (native == VpnNativeStatus.connected ||
            native == VpnNativeStatus.connecting ||
            native == VpnNativeStatus.preparing ||
            native == VpnNativeStatus.error) {
          break;
        }
        await Future<void>.delayed(Duration(milliseconds: 200 * (attempt + 1)));
      }
      native ??= VpnNativeStatus.unknown;

      if (native == VpnNativeStatus.connected) {
        _autoReconnectArmed = false;
        // Seed before EventChannel idle can demote (cold-start race).
        _lastSessionPhase = VpnSessionPhase.connectedHealthy;
        await _hydrateConnectedUi();
        if (!shouldApplyNativeConnected(
              ui: state,
              sessionProving: _sessionProving,
            ) &&
            state is! VpnConnected) {
          return;
        }
        await _enterConnected(freshSession: false);
        return;
      }
      if (native == VpnNativeStatus.connecting ||
          native == VpnNativeStatus.preparing) {
        if (_sessionOwnsUi) return;
        if (state is VpnDisconnected || state is VpnError) {
          state = const VpnConnecting(progress: 0.5);
          _armConnectingPoll();
        }
        return;
      }
      if (native == VpnNativeStatus.error) {
        if (_sessionOwnsUi) return;
        state = await _vpnErrorFromNative();
        return;
      }
      if (native == VpnNativeStatus.idle || native == VpnNativeStatus.unknown) {
        if (_sessionWalkActive || _sessionOwnsUi) return;
        // After 5 getStatus probes the TUN is down. Do not keep or re-paint
        // Nest Connected from a stale ConnectedHealthy (restore / resume).
        if (state is VpnConnected) {
          _vpnLog(
            'vpn.native idle_drop phase=${_lastSessionPhase.name} '
            'ui=${vpnUiPhase(state)}',
          );
          await _confirmIdleDrop(force: true);
          // iOS may tear NEVPN without our stop; sessionActive (KEY_ACTIVE) means
          // the user still wants VPN — reconnect without requiring Settings toggle.
          await _reconnectIfSessionActive(reason: 'idle_drop_connected');
          return;
        }
        if (state is VpnConnecting) {
          await _failConnectingIdle();
          return;
        }
        // Session marked active on disk but tunnel down (force-stop / OEM kill):
        // honour Settings → Auto-reconnect. Never reconnect after intentional stop
        // (native clears `active`).
        final sessionActive = await VpnController.instance.hasActiveSession();
        final shouldReconnect = !_suppressAutoReconnect &&
            sessionActive &&
            await AutoReconnectPrefs.isEnabled();
        if (shouldReconnect) {
          if (_connectInFlight != null || _autoReconnectArmed) {
            _vpnLog('[VPN] syncFromNative: auto-reconnect already in flight');
            return;
          }
          _autoReconnectArmed = true;
          _vpnLog(
            '[VPN] syncFromNative: idle+active session, auto-reconnect → connect()',
          );
          try {
            await connect();
          } finally {
            _autoReconnectArmed = false;
          }
        }
      }
    } catch (e) {
      ProductLog.event(
        'vpn.sync',
        level: ProductLogLevel.error,
        fields: {'error': e.runtimeType.toString()},
      );
      _vpnLog('[VPN] syncFromNative failed: $e');
    } finally {
      _nativeSyncComplete = true;
    }
  }

  void _disposeLocalOnly() {
    _cancelConnectingWatchdog();
    _cancelDisconnectWatchdog();
    _endSessionWalk();
    _sessionOwnsUi = false;
    _sessionProving = false;
    _cancelWifiRetry();
    _cancelStatusSubscriptions();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _connectInFlight = null;
    _autoReconnectArmed = false;
    _enterConnectedGenInFlight = null;
    _egressProbeToken++;
  }

  Future<void> _onAutoPathIncompatible({
    required String reason,
    String? underlying,
    VpnPathTransport transport = VpnPathTransport.unknown,
  }) async {
    var iface = underlying?.trim();
    if (iface == null ||
        iface.isEmpty ||
        iface == '(unknown)' ||
        iface.toLowerCase() == 'unknown') {
      try {
        iface = await VpnController.instance.getUnderlyingNetworkInterface();
      } catch (_) {
        iface = null;
      }
    }
    if (iface == '(unknown)' || iface?.toLowerCase() == 'unknown') {
      iface = null;
    }
    final wifi = isWifiUnderlying(iface: iface, transport: transport);
    ProductLog.event(
      'vpn.connect_fail',
      level: ProductLogLevel.error,
      fields: {
        'code': kVpnPathIncompatibleErrorCode,
        'reason': reason,
        'underlying': iface,
        'attempt': _autoConnectAttempt,
      },
    );
    if (shouldRetryAutoOnWifi(
      alreadyRetried: _wifiAutoRetryUsed,
      userStopping: _suppressAutoReconnect,
      isWifi: wifi,
    )) {
      _wifiAutoRetryUsed = true;
      _autoConnectAttempt = 2;
      _wifiRetryPending = true;
      _vpnLog('[VPN] wifi auto retry after path_incompatible iface=$iface');
      state = const VpnConnecting(progress: 0.45);
      _wifiRetryTimer?.cancel();
      _wifiRetryTimer = Timer(const Duration(milliseconds: 1500), () {
        if (_suppressAutoReconnect) {
          _wifiRetryPending = false;
          return;
        }
        _wifiRetryPending = false;
        unawaited(connect(forceRestart: true, wifiRetry: true));
      });
      return;
    }
    _endSessionWalk();
    _cancelConnectingWatchdog();
    state = const VpnError(
      message: kVpnPathIncompatibleErrorCode,
      code: kVpnPathIncompatibleErrorCode,
    );
  }

  /// Explicit stop → start so route-mode / site prefs enter the next runtime config.
  Future<bool> reconnectToApplyRouting() async {
    final wasConnected = state is VpnConnected || state is VpnConnecting;
    if (!wasConnected) {
      await connect(forceRestart: true);
      return state is VpnConnected;
    }
    _reconnectTimer?.cancel();
    _cancelStatusSubscriptions();
    try {
      await VpnController.instance.stop(reason: 'routing_apply');
    } catch (_) {}
    // Native status can lag behind stop(); wait so connect() doesn't no-op sync.
    for (var i = 0; i < 25; i++) {
      final s = await VpnController.instance.getStatus();
      if (s != VpnNativeStatus.connected && s != VpnNativeStatus.connecting) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    await _clearConnectedSince();
    state = const VpnDisconnected();
    await connect(forceRestart: true);
    return state is VpnConnected;
  }

  Future<void> connect({
    bool forceRestart = false,
    bool reuseConfig = false,
    bool wifiRetry = false,
  }) async {
    // Deduplicate concurrent connect() (auto-reconnect + nest tap).
    _suppressAutoReconnect = false;
    if (!wifiRetry) {
      _cancelWifiRetry();
      _wifiAutoRetryUsed = false;
      _autoConnectAttempt = 1;
    }
    if (_connectInFlight != null) {
      final switching = forceRestart &&
          hideInAppPlategaCheckout &&
          await _selectedHost() != _handshakeHost;
      if (!switching) return _connectInFlight!;
      _connectGeneration++;
      final pending = _connectInFlight!;
      _connectInFlight = null;
      unawaited(pending);
    }
    if (!forceRestart && state is VpnConnected) return;

    final gen = ++_connectGeneration;
    _activeConnectGen = gen;
    _connectInFlight = _connectBody(
      forceRestart: forceRestart,
      reuseConfig: reuseConfig,
      gen: gen,
    ).whenComplete(() {
      if (_activeConnectGen == gen) {
        _activeConnectGen = null;
      }
      _connectInFlight = null;
      _autoReconnectArmed = false;
    });
    return _connectInFlight!;
  }

  Future<void> _connectBody({
    bool forceRestart = false,
    bool reuseConfig = false,
    required int gen,
  }) async {
    final native = await VpnController.instance.getStatus();
    if (native == VpnNativeStatus.connected ||
        native == VpnNativeStatus.connecting ||
        native == VpnNativeStatus.preparing) {
      await VpnController.instance.stop(reason: 'restart');
    }
    if (hideInAppPlategaCheckout) {
      final imported = await Hy2ImportStore.instance.selected();
      if (await _abortStaleConnect(gen)) return;
      if (imported == null) {
        state = const VpnDisconnected();
        return;
      }
    }
    // Conflict before Connecting — foreign VPN must not paint a spinner.
    final existing = await VpnController.instance.getStatus();
    if (await _abortStaleConnect(gen)) return;
    final preConflict = await VpnController.instance.queryVpnConflict();
    if (preConflict.foreignAlwaysOn) {
      state = await _vpnErrorFromConflict(preConflict);
      return;
    }
    // Already up in the system tray (UI lost state after Activity recreate).
    if (!forceRestart && existing == VpnNativeStatus.connected) {
      await _syncFromNative();
      return;
    }
    if (!forceRestart &&
        (existing == VpnNativeStatus.connecting ||
            existing == VpnNativeStatus.preparing)) {
      final sessionActive = await VpnController.instance.hasActiveSession();
      if (sessionActive) {
        await _syncFromNative();
        if (state is VpnConnected) return;
        if (state is VpnConnecting) {
          _armConnectingPoll();
          return;
        }
      }
    }
    if (state is VpnError || state is VpnDisconnected) {
      state = const VpnConnecting(progress: 0.0);
    }
    if (hideInAppPlategaCheckout && forceRestart) {
      final dial = ++_dialGen;
      state = const VpnConnecting(progress: 0.2);
      final busy = existing == VpnNativeStatus.connected ||
          existing == VpnNativeStatus.connecting ||
          existing == VpnNativeStatus.preparing ||
          existing == VpnNativeStatus.disconnecting;
      if (busy) {
        _switchStop = true;
        var idle = false;
        try {
          try {
            await VpnController.instance.wipeSession(reason: 'switch_server');
          } catch (_) {}
          idle = await waitUntilNativeIdle(
            timeout: const Duration(seconds: 8),
          );
        } finally {
          _switchStop = false;
        }
        if (await _abortStaleConnect(gen)) return;
        if (_dialGen != dial) return;
        if (!idle) {
          state = const VpnError(
            message: 'switch_not_idle',
            code: 'switch_not_idle',
          );
          return;
        }
      }
    } else if (forceRestart && existing == VpnNativeStatus.connected) {
      try {
        await VpnController.instance.stop(reason: 'force_restart');
      } catch (_) {}
      if (await _abortStaleConnect(gen)) return;
    }

    if (await _abortStaleConnect(gen)) return;
    _beginSessionWalk();
    state = const VpnConnecting(progress: 0.0);
    _armConnectingPoll();

    try {
      state = const VpnConnecting(progress: 0.3);

      // 2. Проверяем permission (на Android открывает системный диалог)
      final hasPermission = await VpnController.instance.requestPermission();
      if (await _abortStaleConnect(gen)) return;
      if (!hasPermission) {
        state = await _errorForPermissionFailure();
        return;
      }
      // Android 13+: without this the Amnezia-style VPN card stays hidden.
      await VpnController.instance.requestNotificationPermission();
      if (await _abortStaleConnect(gen)) return;
      state = const VpnConnecting(progress: 0.5);

      if (hideInAppPlategaCheckout) {
        // ADR 026: pasted profile only. Do not call GET /vpn/config.
        var imported = await Hy2ImportStore.instance.selected();
        if (await _abortStaleConnect(gen)) return;
        if (imported != null && isUnspecifiedShareHost(imported.endpoint)) {
          final catalog = await Hy2ImportStore.instance.selectedCatalog();
          final url = catalog?.url?.trim() ?? '';
          if (url.isNotEmpty) {
            try {
              await Hy2ImportStore.instance.refreshCatalog(catalog!.id);
            } on SubscriptionDocumentException catch (error) {
              state = VpnError(message: error.code, code: error.code);
              return;
            }
            if (await _abortStaleConnect(gen)) return;
            imported = await Hy2ImportStore.instance.selected();
          }
        }
        if (imported == null) {
          state = const VpnError(
            message: 'hy2_import_required',
            code: 'hy2_import_required',
          );
          return;
        }
        if (isUnspecifiedShareHost(imported.endpoint)) {
          state = const VpnError(
            message: 'client_refused',
            code: 'client_refused',
          );
          return;
        }
        _config = null;
        _autoActiveNodeId = null;
        _catalogHost = null;
        final shown = labelForShareLink(imported);
        _displayLabel = shown.title;
        _selectedNodeProtocol = imported.scheme;
        _profileHost = profileHostForLog(imported.endpoint);
        _sid = ShareSessionLog.nextSid();
        _coreStartLogged = false;
        _sessionFields = ShareSessionLog.fieldsFor(imported);
        ShareSessionLog.emit(
          'vpn.connect_begin',
          level: ProductLogLevel.info,
          sid: _sid,
          fields: _sessionFields,
          extra: {'gen': gen},
        );
        SessionTrace.begin(_sid);
        await VpnSessionMeta.clear();
        final blocked = await SplitTunnelPrefs.loadDisallowedPackages();
        SessionTrace.mark('profile', {'scheme': imported.scheme});
        SessionTrace.mark('per_app', {
          'mode': blocked.isEmpty ? 'all' : 'bypass',
          'apps': blocked.length,
        });
        final profile = imported.hy2?.profile;
        var started = false;
        SessionTrace.mark('config', {'scheme': imported.scheme});
        if (profile != null) {
          final dial = _dialGen == 0 ? ++_dialGen : _dialGen;
          _handshakeHost = imported.endpoint;
          _nativeGenFloor = _lastNativeGen;
          final raw = await VpnController.instance.startHysteria(
            profile,
            displayLabel: shown.title,
          );
          started = raw && _dialGen == dial;
        } else if (canDialScheme(imported.scheme, ios: false) &&
            defaultTargetPlatform == TargetPlatform.android) {
          final xrayJson = buildXraySocksConfig(imported);
          if (xrayJson == null) {
            SessionTrace.mark('fail', {'code': 'share_unsupported'});
            state = const VpnError(
              message: 'share_unsupported',
              code: 'share_unsupported',
            );
            return;
          }
          SessionTrace.mark('dns', {'dns': 'system'});
          started = await VpnController.instance.startXray(
            xrayJson,
            displayLabel: shown.title,
          );
        } else {
          SessionTrace.mark('fail', {'code': 'share_ios_hy2_only'});
          state = const VpnError(
            message: 'share_ios_hy2_only',
            code: 'share_ios_hy2_only',
          );
          return;
        }
        if (await _abortStaleConnect(gen)) return;
        if (!started) {
          SessionTrace.mark('fail', {'code': 'start'});
          state = await _errorForStartFailure();
          return;
        }
        SessionTrace.mark('vpn_service');
        state = const VpnConnecting(progress: 0.8);
        await _waitUntilHandshakeSettles(gen);
        return;
      }

      state = const VpnError(
        message: 'hy2_import_required',
        code: 'hy2_import_required',
      );
    } catch (e, st) {
      if (await _abortStaleConnect(gen)) return;
      _cancelConnectingWatchdog();
      _vpnLog('[VPN] connect failed: $e\n$st');
      ProductLog.event(
        'vpn.connect_fail',
        level: ProductLogLevel.error,
        fields: {
          'code': e is DioException
              ? (e.error ?? e.response?.statusCode)
              : e.runtimeType,
          'message': e.toString(),
        },
      );
      if (e is DioException) {
        final code = e.response?.statusCode ?? 0;
        if (e.error == 'device_limit_reached') {
          state = const VpnError(
            message: 'device_limit_reached',
            code: 'device_limit_reached',
          );
          return;
        }
        if (e.error == 'quota_exceeded' ||
            _apiErrorCode(e) == 'quota_exceeded') {
          state = const VpnError(
            message: 'quota_exceeded',
            code: 'quota_exceeded',
          );
          return;
        }
        if (e.error == 'tt_provision_failed' ||
            _apiErrorCode(e) == 'tt_provision_failed') {
          state = const VpnError(
            message: 'tt_provision_failed',
            code: 'tt_provision_failed',
          );
          return;
        }
        if (e.error == 'hmac_required' || e.error == 'device_revoked') {
          state = VpnError(
            message: e.error as String,
            code: e.error as String,
          );
          return;
        }
        if (code == 401 || e.error == 'session_expired') {
          state = const VpnError(
            message: 'session_expired',
            code: 'session_expired',
          );
          return;
        }
        if (e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.connectionTimeout) {
          state = const VpnError(
            message: 'no_network',
            code: 'no_network',
          );
          return;
        }
      }
      state = VpnError(
        message:
            'Connect failed: ${e is VpnControllerException ? e.message : e}',
      );
    } finally {
      if (state is! VpnConnecting) {
        _endSessionWalk();
        _cancelConnectingWatchdog();
      }
    }
  }

  /// Call from Home [AppLifecycleState.resumed] (sync native status).
  Future<void> onAppResumed() async {
    await syncFromNative();
    if (state is VpnDisconnected || state is VpnError) {
      await reconcileWithNative();
    }
  }

  /// Block auto-reconnect (device self-revoke / intentional stop side-effects).
  void suppressAutoReconnect() {
    _suppressAutoReconnect = true;
    _cancelWifiRetry();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _autoReconnectArmed = false;
  }

  Future<void> disconnect({
    String reason = 'user_tap',
    bool wipeNativeSession = false,
  }) async {
    _connectGeneration++;
    _activeConnectGen = null;
    _cancelConnectingWatchdog();
    _cancelWifiRetry();
    _reconnectTimer?.cancel();
    _suppressAutoReconnect = true;
    _endSessionWalk();
    _sessionOwnsUi = false;
    _sessionProving = false;
    _lastSessionPhase = VpnSessionPhase.stopping;
    // Always allow cancel while UI shows connecting (incl. stuck preparing).
    final native = await VpnController.instance.getStatus();
    ShareSessionLog.emit(
      'vpn.disconnect',
      level: ProductLogLevel.info,
      sid: _sid,
      extra: {'reason': reason, 'native_before': native.name},
    );
    final uiBusy = state is VpnConnected || state is VpnConnecting;
    final nativeBusy = native == VpnNativeStatus.connected ||
        native == VpnNativeStatus.connecting ||
        native == VpnNativeStatus.preparing;
    if (!uiBusy && !nativeBusy) {
      _lastSessionPhase = VpnSessionPhase.idle;
      state = const VpnDisconnected();
      if (wipeNativeSession) {
        try {
          await VpnController.instance
              .wipeSession(reason: reason)
              .timeout(const Duration(seconds: 10));
        } catch (e) {
          ProductLog.event(
            'vpn.disconnect',
            level: ProductLogLevel.error,
            fields: {'reason': 'wipe', 'error': e.runtimeType.toString()},
          );
          _vpnLog('[VPN] idle wipeSession error: $e');
          rethrow;
        }
      }
      return;
    }
    _recordSessionEnd();
    _egressProbeToken++;
    if (state is VpnConnecting || state is VpnConnected) {
      state = const VpnConnecting(progress: 0.5); // disconnecting affordance
    }

    // If stop() hangs, don't leave Nest spinning forever.
    _cancelDisconnectWatchdog();
    _disconnectWatchdog = Timer(const Duration(seconds: 10), () async {
      ProductLog.event(
        'vpn.disconnect',
        level: ProductLogLevel.warn,
        fields: {'reason': 'watchdog'},
      );
      _vpnLog('[VPN] disconnect watchdog fired ui=$state');
      _connectInFlight = null;
      final still = await VpnController.instance.getStatus();
      if (still == VpnNativeStatus.connected && !_suppressAutoReconnect) {
        await _enterConnected(freshSession: false);
      } else {
        await _clearConnectedSince();
        _lastSessionPhase = VpnSessionPhase.idle;
        state = const VpnDisconnected();
      }
    });

    try {
      final stop = wipeNativeSession
          ? VpnController.instance.wipeSession(reason: reason)
          : VpnController.instance.stop(reason: reason);
      await stop.timeout(const Duration(seconds: 10));
    } on TimeoutException catch (e) {
      ProductLog.event(
        'vpn.disconnect',
        level: ProductLogLevel.warn,
        fields: {'reason': 'timeout'},
      );
      _vpnLog('[VPN] disconnect stop timeout: $e');
      if (wipeNativeSession) rethrow;
    } catch (e) {
      ProductLog.event(
        'vpn.disconnect',
        level: ProductLogLevel.error,
        fields: {'reason': 'stop', 'error': e.runtimeType.toString()},
      );
      _vpnLog('[VPN] disconnect error: $e');
      if (wipeNativeSession) rethrow;
    } finally {
      final after = await VpnController.instance.getStatus();
      ShareSessionLog.emit(
        'vpn.disconnect',
        level: ProductLogLevel.info,
        sid: _sid,
        extra: {'native_after': after.name},
      );
      _cancelDisconnectWatchdog();
      _cancelStatusSubscriptions();
      _autoReconnectArmed = false;
      _connectInFlight = null;
      _subscribeToStatus();
      if (after == VpnNativeStatus.connected && !_suppressAutoReconnect) {
        // stop did not tear down — stay honest with native.
        await _enterConnected(freshSession: false);
      } else {
        await _clearConnectedSince();
        _lastSessionPhase = VpnSessionPhase.idle;
        state = const VpnDisconnected();
      }
    }
  }

  String? _lastLoggedIface;

  String _sessionScheme(String protocol) {
    final selected = _selectedNodeProtocol?.trim();
    if (selected != null && selected.isNotEmpty) return selected;
    if (protocol.toUpperCase() == 'HYSTERIA2') return 'hysteria2';
    return protocol.toLowerCase();
  }

  void _rememberFreeSession(String sessionKey) {
    if (!freeKeyClient) return;
    _freeSessionOpen = true;
    _freeSessionKey = sessionKey;
  }

  void _recordSessionEnd() {
    _freeSessionOpen = false;
    _freeSessionKey = null;
    final current = state;
    if (current is! VpnConnected) return;
    final seconds = DateTime.now().difference(current.connectedSince).inSeconds;
    ProductLog.event(
      'vpn.session_end',
      level: ProductLogLevel.info,
      fields: {
        'duration_s': seconds,
        'profile': current.serverName,
        'scheme': _sessionScheme(current.protocol),
        'host': _profileHost,
      },
    );
  }

  /// Попытка автоматического переподключения через 5 сек (если включено в Settings).
  void _scheduleReconnect() {
    if (freeKeyClient) {
      _vpnLog('[VPN] Flutter reconnect skipped; native owns free client');
      return;
    }
    if (_suppressAutoReconnect) {
      _vpnLog('[VPN] auto-reconnect suppressed (intentional stop/revoke)');
      return;
    }
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () async {
      if (_suppressAutoReconnect) return;
      final enabled = await AutoReconnectPrefs.isEnabled();
      if (!enabled) {
        _vpnLog('[VPN] auto-reconnect skipped (disabled in Settings)');
        return;
      }
      final sessionActive = await VpnController.instance.hasActiveSession();
      if (!sessionActive) {
        _vpnLog('[VPN] auto-reconnect skipped (session not active)');
        return;
      }
      if (state is VpnConnected || state is VpnConnecting) return;
      _vpnLog('[VPN] attempting auto-reconnect...');
      await connect();
    });
  }

  void _cancelStatusSubscriptions() {
    _statusSubscription?.cancel();
    _statusSubscription = null;
    _sessionSubscription?.cancel();
    _sessionSubscription = null;
  }

  void _subscribeToStatus() {
    _statusSubscription ??= VpnController.instance.statusStream.listen(
      _onNativeStatus,
      onError: (Object e) {
        ProductLog.event(
          'vpn.status_stream',
          level: ProductLogLevel.error,
          fields: {'error': e.runtimeType.toString()},
        );
        _vpnLog('[VPN] statusStream error: $e');
      },
    );
    _sessionSubscription ??= VpnController.instance.sessionStream.listen(
      _onSessionSnapshot,
      onError: (Object e) {
        ProductLog.event(
          'vpn.session_stream',
          level: ProductLogLevel.error,
          fields: {'error': e.runtimeType.toString()},
        );
        _vpnLog('[VPN] sessionStream error: $e');
      },
    );
  }

  void _onSessionSnapshot(VpnSessionSnapshot snap) {
    if (shouldIgnoreRegressiveIdleSnapshot(
      incoming: snap.phase,
      lastPhase: _lastSessionPhase,
      walkActive: _sessionWalkActive,
      sessionOwnsUi: _sessionOwnsUi,
      userStopping: _suppressAutoReconnect || _switchStop,
    )) {
      _vpnLog(
        'vpn.native ignore regressive ${snap.phase.name} '
        'last=${_lastSessionPhase.name} ui=${vpnUiPhase(state)}',
      );
      return;
    }
    _lastNativeGen = snap.generation;
    _lastSessionPhase = snap.phase;
    _sessionOwnsUi = snap.ownsConnectUi;
    final wasProving = _sessionProving;
    _sessionProving = snap.ignoresNativeConnected;
    // Auto-prove can exceed 18s; restart the hung-Connecting clock after it.
    if (wasProving && !_sessionProving && state is VpnConnecting) {
      _connectingUiStartedAt = DateTime.now();
    }
    if (snap.isProving) {
      if (!freeKeyClient) {
        final proveId = snap.candidateId ?? '';
        if (proveId.isNotEmpty && proveId != _lastLoggedProveId) {
          _lastLoggedProveId = proveId;
          _lastProveSummary = 'id=$proveId proving';
          ProductLog.event(
            'vpn.prove',
            level: ProductLogLevel.debug,
            fields: {'id': proveId, 'ok': 'pending'},
          );
        }
      }
    }
    if (snap.isConnected) {
      if (hideInAppPlategaCheckout &&
          (snap.generation <= _nativeGenFloor || _switchStop)) {
        return;
      }
      if (hideInAppPlategaCheckout) {
        _liveDialGen = _dialGen;
      }
      final proveId = snap.candidateId ?? _autoActiveNodeId ?? '';
      _lastProveSummary = 'id=$proveId ok reason=${snap.reason.name}';
      _cancelConnectingWatchdog();
      final alreadyOn = state is VpnConnected;
      if (!freeKeyClient && !alreadyOn) {
        ProductLog.event(
          'vpn.prove',
          level: ProductLogLevel.info,
          fields: {
            'id': proveId,
            'ok': true,
            'reason': snap.reason.name,
          },
        );
      }
      if (_freeSessionOpen) return;
      unawaited(
        _enterConnected(freshSession: !alreadyOn && state is VpnConnecting),
      );
      return;
    }
    if (snap.phase == VpnSessionPhase.error) {
      final pathIncompatible = snap.reason ==
              VpnSessionReason.pathIncompatible ||
          (snap.detail?.toLowerCase().contains('path_incompatible') ?? false);
      if (pathIncompatible) {
        unawaited(
          _onAutoPathIncompatible(
            reason: snap.detail ?? snap.reason.name,
            underlying: snap.underlyingIface,
            transport: snap.transport,
          ),
        );
        return;
      }
      _endSessionWalk();
      _cancelConnectingWatchdog();
      _lastProveSummary = 'id=${snap.candidateId} fail ${snap.reason.name}';
      ProductLog.event(
        'vpn.connect_fail',
        level: ProductLogLevel.error,
        fields: {
          'code': snap.reason.name,
          'detail': snap.detail,
          'underlying': snap.underlyingIface,
          'attempt': _autoConnectAttempt,
        },
      );
      state = vpnErrorFromSession(snap);
      return;
    }
    if (snap.phase == VpnSessionPhase.idle &&
        state is VpnConnecting &&
        !_sessionWalkActive &&
        _connectInFlight == null) {
      unawaited(_failConnectingIdle());
      return;
    }
    if (snap.phase == VpnSessionPhase.idle &&
        _suppressAutoReconnect &&
        state is VpnConnected) {
      unawaited(_confirmIdleDrop());
      return;
    }
    if (!snap.ownsConnectUi) return;
    if (state is! VpnConnecting) {
      state = const VpnConnecting(progress: 0.55);
    }
  }

  void _onNativeStatus(VpnNativeStatus nativeStatus) {
    switch (nativeStatus) {
      case VpnNativeStatus.connected:
        if (_suppressAutoReconnect) return;
        _logCoreStart(ok: true);
        if (state is VpnConnected) return;
        // SOCKS prove: ignore native connected. Binding+TUN (shade Connected)
        // must paint Nest. Confirmed TUN up heals sticky VpnError.
        if (!shouldApplyNativeConnected(
          ui: state,
          sessionProving: _sessionProving,
        )) {
          return;
        }
        final fresh = state is VpnConnecting;
        unawaited(_enterConnected(freshSession: fresh));
      case VpnNativeStatus.disconnecting:
        break;
      case VpnNativeStatus.idle:
        if (_sessionWalkActive || _sessionOwnsUi) return;
        if (_idleMustNotDemote()) {
          return;
        }
        if (state is VpnConnecting && _connectInFlight == null) {
          unawaited(_failConnectingIdle());
        } else if (state is VpnConnected) {
          unawaited(() async {
            await _confirmIdleDrop();
            await _reconnectIfSessionActive(reason: 'native_idle_event');
          }());
        }
      case VpnNativeStatus.revoked:
        _endSessionWalk();
        _sessionOwnsUi = false;
        _sessionProving = false;
        final wasConnected = state is VpnConnected;
        if (wasConnected) _recordSessionEnd();
        unawaited(_clearConnectedSince());
        state = const VpnError(message: 'VPN was revoked by system');
        ProductLog.event(
          'vpn.connect_fail',
          level: ProductLogLevel.error,
          fields: {'code': 'revoked'},
        );
        if (wasConnected) {
          _scheduleReconnect();
        }
      case VpnNativeStatus.error:
        _logCoreStart(ok: false);
        if (_sessionOwnsUi) return;
        if (state is VpnError) return;
        final wasConnected = state is VpnConnected;
        final wasConnecting = state is VpnConnecting;
        if (wasConnected) _recordSessionEnd();
        unawaited(_clearConnectedSince());
        unawaited(
          _vpnErrorFromNative().then((err) {
            if (_sessionOwnsUi || state is VpnError) return;
            ProductLog.event(
              'vpn.connect_fail',
              level: ProductLogLevel.error,
              fields: {
                'code': err.code,
                'message': err.message,
                'host': _profileHost,
              },
            );
            if (err.message.contains('tcp=')) {
              ShareSessionLog.emit(
                'vpn.server_tcp',
                level: ProductLogLevel.error,
                sid: _sid,
                extra: {'detail': err.message},
              );
            }
            state = err;
          }),
        );
        if (wasConnected && !wasConnecting) {
          _scheduleReconnect();
        }
      case VpnNativeStatus.unknown:
      case VpnNativeStatus.preparing:
      case VpnNativeStatus.connecting:
        if (_sessionOwnsUi) return;
        // Do not resurrect Connecting from a stale EventChannel replay after
        // destroy / Auto fail / user disconnect (_connectInFlight is null).
        if (_connectInFlight == null && state is! VpnConnecting) break;
        if (state is VpnDisconnected || state is VpnError) {
          state = const VpnConnecting(progress: 0.5);
          _armConnectingPoll();
        }
    }
  }

  Future<void> _failConnectingFromNative() async {
    if (_sessionOwnsUi) return;
    if (state is! VpnConnecting) return;
    _cancelConnectingWatchdog();
    await _clearConnectedSince();
    state = await _vpnErrorFromNative();
  }

  Future<void> _failConnectingIdle() async {
    if (!_shouldDropConnectingOnIdle()) return;
    await _clearConnectedSince();
    if (!_shouldDropConnectingOnIdle()) return;
    _cancelConnectingWatchdog();
    _endSessionWalk();
    if (_suppressAutoReconnect) {
      state = const VpnDisconnected();
      return;
    }
    final detail = await VpnController.instance.getLastError();
    if (!_shouldDropConnectingOnIdle()) return;
    if (detail != null && detail.trim().isNotEmpty) {
      state = vpnErrorFromNativeDetail(detail);
      return;
    }
    state = const VpnDisconnected();
  }

  /// Hung Connecting: foreign VPN CTA only when conflict is real; else timeout.
  Future<void> _failConnectingStuck() async {
    _cancelConnectingWatchdog();
    if (state is! VpnConnecting) return;
    _suppressAutoReconnect = true;
    _endSessionWalk();
    _sessionOwnsUi = false;
    _sessionProving = false;
    await _clearConnectedSince();
    final conflict = await VpnController.instance.queryVpnConflict();
    if (conflict.foreignAlwaysOn || conflict.foreignVpnActive) {
      ProductLog.event(
        'vpn.connect_fail',
        level: ProductLogLevel.error,
        fields: {'code': 'conflict'},
      );
      _vpnLog('[VPN] connecting stuck — conflict CTA');
      state = await _vpnErrorFromConflict(conflict);
      return;
    }
    // iOS has no getVpnConflict — do not paint Android "another VPN" copy.
    ProductLog.event(
      'vpn.connect_fail',
      level: ProductLogLevel.error,
      fields: {'code': kVpnConnectTimeoutErrorCode},
    );
    _vpnLog('[VPN] connecting stuck — connect_timeout');
    final detail = await VpnController.instance.getLastError();
    if (detail != null && detail.trim().isNotEmpty) {
      state = VpnError(
        message: detail.trim(),
        code: kVpnConnectTimeoutErrorCode,
      );
      return;
    }
    state = const VpnError(
      message: kVpnConnectTimeoutErrorCode,
      code: kVpnConnectTimeoutErrorCode,
    );
  }

  /// Don't flip UI to disconnected on a single idle event — re-check native.
  /// [force] skips Always-on flap protection after syncFromNative already
  /// probed idle several times (restore / resume fake Connected).
  Future<void> _confirmIdleDrop({bool force = false}) async {
    if (!force && _idleMustNotDemote()) {
      return;
    }
    if (!force) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (_idleMustNotDemote()) {
        return;
      }
    }
    final native = await VpnController.instance.getStatus();
    if (native == VpnNativeStatus.connected ||
        native == VpnNativeStatus.connecting ||
        native == VpnNativeStatus.preparing) {
      if (state is! VpnConnected) {
        await _enterConnected(freshSession: false);
      }
      return;
    }
    if (state is VpnConnected) {
      _recordSessionEnd();
      await _clearConnectedSince();
      _lastSessionPhase = VpnSessionPhase.idle;
      state = const VpnDisconnected();
    }
  }

  /// After unexpected native idle: if the user still wants VPN (sessionActive),
  /// start again. Intentional stop clears sessionActive on iOS/Android.
  Future<void> _reconnectIfSessionActive({required String reason}) async {
    if (freeKeyClient) {
      _vpnLog(
          '[VPN] reconnect skipped; native owns free client reason=$reason');
      return;
    }
    if (_suppressAutoReconnect) return;
    if (_connectInFlight != null || _autoReconnectArmed) {
      _vpnLog('[VPN] reconnect skip in-flight reason=$reason');
      return;
    }
    final live = await VpnController.instance.getStatus();
    if (live == VpnNativeStatus.connected) {
      // Already up — hydrate UI only; do not start a second tunnel.
      _vpnLog('[VPN] reconnect skip already_connected reason=$reason');
      if (state is! VpnConnected) {
        await _enterConnected(freshSession: false);
      }
      return;
    }
    if (!await AutoReconnectPrefs.isEnabled()) {
      _vpnLog('[VPN] reconnect skip disabled reason=$reason');
      return;
    }
    final sessionActive = await VpnController.instance.hasActiveSession();
    if (!sessionActive) return;
    _autoReconnectArmed = true;
    _vpnLog('[VPN] syncFromNative: $reason sessionActive → connect()');
    try {
      await connect();
    } finally {
      _autoReconnectArmed = false;
    }
  }
}

void _vpnLog(String message) {
  if (kDebugMode) debugPrint(message);
}

String? _apiErrorCode(DioException e) {
  final detail = e.response?.data;
  if (detail is! Map) return null;
  final nested = detail['detail'];
  if (nested is Map && nested['error'] is Map) {
    final code = (nested['error'] as Map)['code'];
    return code is String ? code : null;
  }
  return null;
}

final vpnProvider = NotifierProvider<VpnNotifier, VpnStatus>(
  VpnNotifier.new,
);
