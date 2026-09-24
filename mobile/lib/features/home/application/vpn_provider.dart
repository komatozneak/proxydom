import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api_secret_storage.dart';
import '../../../core/app_locale.dart';
import '../../../core/diagnostics/app_log_buffer.dart';
import '../../../core/diagnostics/egress_verify.dart';
import '../../../core/diagnostics/product_log.dart';
import '../../../core/ios_store_gates.dart';
import '../../../core/jwt_interceptor.dart';
import '../../../core/retry_policy.dart';
import '../../auth/application/auth_provider.dart';
import '../../auth/application/auth_state.dart';
import '../../beta/application/beta_usage_tracker.dart';
import '../../vpn/data/hy2_import_store.dart';
import '../../vpn/data/subscription_label.dart';
import '../../vpn/data/xray_share_config.dart';
import '../../vpn/data/node_auto_selector.dart';
import '../../vpn/data/node_display.dart';
import '../../vpn/data/vpn_config.dart';
import '../../vpn/data/vpn_config_repository.dart';
import '../../vpn/data/vpn_controller.dart';
import '../../vpn/data/vpn_node.dart';
import '../../vpn/data/vpn_session_meta.dart';
import '../../vpn/data/vpn_session_snapshot.dart';
import '../../vpn/data/vpn_nodes_repository.dart';
import '../../vpn/data/vpn_service_config.dart';
import '../../vpn/domain/vpn_connect_error.dart';
import '../../settings/application/subscription_status_provider.dart';
import '../../settings/data/auto_reconnect_prefs.dart';
import '../data/external_ip_service.dart';
import 'vpn_status.dart';
import 'vpn_status_log.dart';

/// Singleton-репозиторий для VPN-конфига.
final vpnConfigRepositoryProvider = Provider<VpnConfigRepository>(
  (ref) => VpnConfigRepository(),
);

final vpnNodesRepositoryProvider = Provider<VpnNodesRepository>(
  (ref) => VpnNodesRepository(),
);

/// Retry policy for VPN ops. fetchConfig uses a longer policy for provision_pending.
final _retryPolicy = RetryPolicy(
  maxAttempts: 3,
  initialDelay: const Duration(milliseconds: 500),
  maxDelay: const Duration(seconds: 3),
);

/// ADR 012: match gate/smoke — retry provision_pending with backoff.
final _connectProvisionRetryPolicy = RetryPolicy(
  maxAttempts: 5,
  initialDelay: const Duration(milliseconds: 800),
  maxDelay: const Duration(seconds: 6),
);

/// Auto mint: short wall-clock so Wi-Fi does not stall Connecting before prove.
final _autoMintRetryPolicy = RetryPolicy(
  maxAttempts: 2,
  initialDelay: const Duration(milliseconds: 400),
  maxDelay: const Duration(seconds: 2),
);

const _autoMintTimeout = Duration(seconds: 8);

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
  String? _profileHost;
  bool _freeSessionOpen = false;
  String? _freeSessionKey;

  /// Protocol of the catalog node chosen at fetchConfig / selectNode time
  /// (`kVpnNodeProtocolTrusttunnel` → start TrustTunnel core, ADR 006).
  String? _selectedNodeProtocol;

  /// Auto mints keyed by catalog node id. UI must follow the prove winner,
  /// not the last row in the mint loop (Hy2 is last and stole the card).
  final Map<String, _AutoMint> _autoMints = {};
  String? _autoActiveNodeId;

  /// Последний полученный конфиг. Доступен из UI для preview.
  VpnConfig? get config => _config;

  /// Friendly region label for the active egress hop (read-only Home card).
  String? get displayLabel => _displayLabel;

  /// Auto prove winner catalog id (null when not Auto / not yet proved).
  String? get autoWinnerId => _autoActiveNodeId;

  /// Last prove snapshot for owner reports (id + outcome, no secrets).
  String? get lastProveSummary => _lastProveSummary;

  /// Catalog `VpnNode.host` (IPv4) for the active hop — IP↔IP, not SNI.
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

  Future<bool> _abortStaleConnect(int gen) async {
    if (!_isConnectStale(gen)) return false;
    _vpnLog('[VPN] connect aborted gen=$gen now=$_connectGeneration');
    _endSessionWalk();
    _cancelConnectingWatchdog();
    if (_suppressAutoReconnect &&
        (state is VpnConnecting || state is VpnConnected)) {
      _lastSessionPhase = VpnSessionPhase.idle;
      state = const VpnDisconnected();
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

  /// One PathIncompatible Auto retry on Wi-Fi (issue #147).
  bool _wifiAutoRetryUsed = false;
  bool _wifiRetryPending = false;
  Timer? _wifiRetryTimer;
  String _lastAutoPoolIds = '';
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
        if (!freeKeyClient) {
          try {
            _config ??= await fetchConfig();
          } catch (e) {
            _vpnLog('[VPN] reconcile fetchConfig soft-fail: $e');
          }
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
          _logReconcile(native, before);
        }
    }
  }

  void _logReconcile(VpnNativeStatus native, String before) {
    final after = vpnUiPhase(state);
    if (after == before) return;
    _vpnLog('vpn.reconcile native=${native.name} from=$before to=$after');
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
      await _enterConnected(freshSession: true);
      return;
    }
    if (native == VpnNativeStatus.error) {
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

  void _applyAutoMint(String nodeId) {
    final mint = _autoMints[nodeId];
    if (mint == null) return;
    _config = mint.config;
    _displayLabel = mint.label;
    _selectedNodeProtocol = mint.protocol;
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
    final winner = freeKeyClient ? null : _autoActiveNodeId;
    if (winner != null) {
      _applyAutoMint(winner);
    }
    final config = _config;
    final serverName = connectedServerName(
      config: config,
      displayLabel: _displayLabel,
    );
    final protocol = sessionProtocolLabel(
      config: config,
      selectedNodeProtocol: _selectedNodeProtocol,
    );
    final sessionKey =
        '${_sessionScheme(protocol)}|$_profileHost|$serverName';
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
      ProductLog.event('vpn.connected', {
        'winner_id': _autoActiveNodeId,
        'core': config?.activeCore.name,
        'label': serverName,
        'scheme': _sessionScheme(protocol),
        'host': _profileHost,
      });
      _rememberFreeSession(sessionKey);
      unawaited(
          _persistConnectedUi(serverName: serverName, protocol: protocol));
      unawaited(_persistAutoLastWinner());
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
    ProductLog.event('vpn.connected', {
      'winner_id': _autoActiveNodeId,
      'core': config?.activeCore.name,
      'label': serverName,
      'scheme': _sessionScheme(protocol),
      'host': _profileHost,
    });
    _rememberFreeSession(sessionKey);
    unawaited(_persistConnectedUi(serverName: serverName, protocol: protocol));
    unawaited(_persistAutoLastWinner());
    final probeToken = ++_egressProbeToken;
    unawaited(_logEgressProbe(token: probeToken));
    unawaited(
      VpnController.instance.getUnderlyingNetworkInterface().then((iface) {
        final name = iface?.trim();
        if (name == null || name.isEmpty || name == _lastLoggedIface) return;
        _lastLoggedIface = name;
        ProductLog.event('net.iface', {'name': name});
      }),
    );
    if (freshSession) {
      try {
        ref.read(betaUsageTrackerProvider).recordConnectSuccess();
      } on StateError {
        // Provider disposed in tests.
      }
    }
  }

  Future<void> _hydrateConnectedUi({String? winnerId}) async {
    if (freeKeyClient) {
      await _hydrateImportedProfileUi();
      return;
    }
    final fromSnap = winnerId?.trim();
    if (fromSnap != null && fromSnap.isNotEmpty && fromSnap != kRegionAutoId) {
      _autoActiveNodeId = fromSnap;
      _applyAutoMint(fromSnap);
    }
    if (_displayLabel != null &&
        _displayLabel!.trim().isNotEmpty &&
        _selectedNodeProtocol != null &&
        _selectedNodeProtocol!.trim().isNotEmpty) {
      return;
    }
    try {
      final meta = await VpnSessionMeta.load();
      _displayLabel ??= meta.displayLabel;
      _selectedNodeProtocol ??= meta.protocol;
      if (_autoActiveNodeId == null || _autoActiveNodeId!.isEmpty) {
        final stored = meta.winnerNodeId?.trim();
        if (stored != null && stored.isNotEmpty && stored != kRegionAutoId) {
          _autoActiveNodeId = stored;
          _applyAutoMint(stored);
        }
      }
    } catch (_) {}
    final id = _autoActiveNodeId;
    if (id == null || id.isEmpty || id == kRegionAutoId) return;
    if (_displayLabel != null &&
        _displayLabel!.trim().isNotEmpty &&
        _selectedNodeProtocol != null &&
        _selectedNodeProtocol!.trim().isNotEmpty) {
      return;
    }
    try {
      final repo = ref.read(vpnNodesRepositoryProvider);
      // Disk cache only — listNodes here stampeded /app/nodes/v2 and jammed Nest.
      final catalog = await repo.loadCachedNodes();
      if (catalog == null || catalog.isEmpty) return;
      for (final n in catalog) {
        if (n.id != id) continue;
        _selectedNodeProtocol ??= n.protocol;
        _displayLabel ??= await _labelForNodeId(id, catalog: catalog);
        break;
      }
    } on StateError {
      // tests
    } catch (_) {}
  }

  /// A free key client has no catalog session. The selected local profile owns
  /// user-facing identity; native owns only lifecycle.
  Future<void> _hydrateImportedProfileUi() async {
    _config = null;
    _autoActiveNodeId = null;
    _catalogHost = null;
    final imported = await Hy2ImportStore.instance.selected();
    _displayLabel = imported == null
        ? null
        : labelForShareLink(imported).title;
    _selectedNodeProtocol = imported?.scheme;
    _profileHost = imported == null
        ? null
        : profileHostForLog(imported.endpoint);
  }

  Future<void> _persistConnectedUi({
    required String serverName,
    required String protocol,
  }) async {
    try {
      if (freeKeyClient) {
        // Remove account-era VLESS / winner metadata. Import identity is
        // restored from Hy2ImportStore, never from this catalog cache.
        await VpnSessionMeta.clear();
        return;
      }
      await VpnSessionMeta.saveConnectMeta(
        expectedEgressHost: _config?.expectedEgressHost,
        updateExpectedHost: _config?.expectedEgressHost != null,
        winnerNodeId: _autoActiveNodeId,
        displayLabel: serverName,
        protocol: _selectedNodeProtocol ??
            switch (protocol) {
              'HYSTERIA2' => kVpnNodeProtocolHysteria2,
              'TRUSTTUNNEL' => kVpnNodeProtocolTrusttunnel,
              _ => 'vless',
            },
      );
    } catch (_) {}
  }

  Future<void> _persistAutoLastWinner() async {
    if (freeKeyClient) return;
    final id = _autoActiveNodeId?.trim();
    if (id == null || id.isEmpty || id == kRegionAutoId) return;
    try {
      final repo = ref.read(vpnNodesRepositoryProvider);
      final stored = await repo.getSelectedNodeId();
      final useAuto =
          stored == null || stored.isEmpty || stored == kRegionAutoId;
      if (!useAuto) return;
      await repo.setAutoLastWinnerId(id);
    } on StateError {
      // tests
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
      if (freeKeyClient) {
        _catalogHost = null;
        final ip = await VpnController.instance.provenEgressIp();
        if (mine != _egressProbeToken || state is! VpnConnected) return;
        ProductLog.event('vpn.egress_probe', {
          'external_ip': ip,
          'profile': _displayLabel,
          'scheme': _selectedNodeProtocol,
          'host': _profileHost,
          'phase': _lastSessionPhase.name,
        });
        return;
      }
      var winnerId = _autoActiveNodeId;
      if (winnerId == null || winnerId.isEmpty) {
        final fromProfile = _config?.hysteriaProfile?.nodeId.trim();
        if (fromProfile != null && fromProfile.isNotEmpty) {
          winnerId = fromProfile;
        }
      }
      if (winnerId == null || winnerId.isEmpty || winnerId == kRegionAutoId) {
        try {
          final stored =
              await ref.read(vpnNodesRepositoryProvider).getSelectedNodeId();
          if (stored != null && stored.isNotEmpty && stored != kRegionAutoId) {
            winnerId = stored;
          }
        } on StateError {
          // Provider disposed in tests.
        }
      }
      final catalogHost = await _lookupCatalogHost(winnerId);
      if (mine != _egressProbeToken || state is! VpnConnected) {
        return;
      }
      _catalogHost = catalogHost;
      final ip = await fetchExternalIp();
      if (mine != _egressProbeToken ||
          state is! VpnConnected ||
          _suppressAutoReconnect ||
          _lastSessionPhase == VpnSessionPhase.stopping ||
          _lastSessionPhase == VpnSessionPhase.idle) {
        return;
      }
      final check = egressCheckLabel(externalIp: ip, catalogHost: catalogHost);
      ProductLog.event('vpn.egress_probe', {
        'external_ip': ip,
        'winner_id': winnerId,
        'catalog_host': catalogHost,
        'phase': _lastSessionPhase.name,
        'egress_check': check,
      });
      // `nat` = Hy2/VLESS egress IP ≠ catalog inbound. Not a TUN leak.
    } catch (e) {
      _vpnLog('[VPN] egress_probe failed: $e', warn: true);
    }
  }

  Future<String?> _lookupCatalogHost(String? nodeId) async {
    if (nodeId == null || nodeId.isEmpty || nodeId == kRegionAutoId) {
      return null;
    }
    try {
      final repo = ref.read(vpnNodesRepositoryProvider);
      final cached = await repo.loadCachedNodes();
      final nodes = cached ?? const <VpnNode>[];
      for (final n in nodes) {
        if (n.id == nodeId) {
          final host = n.host.trim();
          return host.isEmpty ? null : host;
        }
      }
    } on StateError {
      // Provider disposed in tests.
    } catch (_) {}
    return null;
  }

  @override
  VpnStatus build() {
    // Real logout only — ignore loading/error auth flaps (no native stop).
    ref.listen<AsyncValue<AuthState>>(authProvider, (prev, next) {
      final wasAuth = prev?.valueOrNull is AuthStateAuthenticated;
      final isAuth = next.valueOrNull is AuthStateAuthenticated;
      if (wasAuth && !isAuth && next.hasValue) {
        // LogoutHandler owns awaited native stop+wipe. This listener only
        // clears local provider state after auth has actually transitioned.
        unawaited(_cleanupLocalAfterLogout());
      }
    });
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
        final line = _nativeStatusLog.lineFor(native);
        if (line != null) _vpnLog(line);
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
        final winner = _autoActiveNodeId;
        if (!freeKeyClient &&
            _config == null &&
            winner != null &&
            winner.isNotEmpty &&
            winner != kRegionAutoId) {
          final keepLabel = _displayLabel;
          final keepProto = _selectedNodeProtocol;
          try {
            _config = await fetchConfig(nodeId: winner);
          } catch (e) {
            _vpnLog('[VPN] syncFromNative fetchConfig soft-fail: $e');
          }
          _displayLabel ??= keepLabel;
          _selectedNodeProtocol ??= keepProto;
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

  Future<void> _cleanupLocalAfterLogout() async {
    _disposeLocalOnly();
    if (state is! VpnDisconnected) {
      state = const VpnDisconnected();
    }
    _config = null;
    _displayLabel = null;
    _profileHost = null;
    _freeSessionOpen = false;
    _freeSessionKey = null;
    _selectedNodeProtocol = null;
    _autoMints.clear();
    _autoActiveNodeId = null;
    _catalogHost = null;
    _wifiAutoRetryUsed = false;
    await _clearConnectedSince();
    try {
      ref.read(vpnConfigRepositoryProvider).clearCache();
    } on StateError {
      // ProviderContainer may already be disposed (unit tests).
    }
  }

  /// Получить конфиг без подключения (для UI/preview).
  ///
  /// Retry на transient ошибках (5xx, network), без retry на 4xx.
  /// Respects persisted region. Auto does **not** mint here — prove loop does.
  Future<VpnConfig> fetchConfig({String? nodeId}) async {
    final nodesRepo = ref.read(vpnNodesRepositoryProvider);
    final stored = nodeId ?? await nodesRepo.getSelectedNodeId();
    final useAuto = stored == null || stored.isEmpty || stored == kRegionAutoId;
    if (useAuto) {
      await nodesRepo.setSelectedNodeId(kRegionAutoId);
    }
      _displayLabel = null;
      _profileHost = null;
      _selectedNodeProtocol = null;
      List<VpnNode>? catalog;
    String? apiNodeId;
    try {
      if (useAuto) {
        catalog = await nodesRepo.listNodes();
        apiNodeId = null;
      } else {
        // Concrete region: prefer disk cache to avoid /vpn/nodes on every switch.
        catalog = await nodesRepo.loadCachedNodes();
        final cachedHasNode =
            catalog != null && catalog.any((n) => n.id == stored);
        if (!cachedHasNode) {
          catalog = await nodesRepo.listNodes();
        }
        apiNodeId = stored;
      }
      _vpnLog('[VPN] selected node_id=$apiNodeId auto=$useAuto');
      if (apiNodeId != null) {
        for (final n in catalog) {
          if (n.id == apiNodeId) {
            _selectedNodeProtocol = n.protocol;
            break;
          }
        }
      }
    } catch (e) {
      _vpnLog('[VPN] node pick failed, using default: $e');
      apiNodeId = useAuto ? null : stored;
    }

    _displayLabel = await _labelForNodeId(apiNodeId, catalog: catalog);

    try {
      return await _connectProvisionRetryPolicy.execute(
        () => ref.read(vpnConfigRepositoryProvider).getConfig(
              forceRefresh: true,
              nodeId: apiNodeId == kRegionAutoId ? null : apiNodeId,
            ),
        shouldRetry: (e) async {
          if (e is FormatException || e is TypeError) return false;
          if (e is DioException) {
            // ADR 012: provision_pending is temporary — retry like smoke scripts.
            if (e.error == 'provision_pending' ||
                _apiErrorCode(e) == 'provision_pending') {
              return true;
            }
            // Не повторяем 4xx — авторизация/клиент; type может быть unknown.
            final code = e.response?.statusCode ?? 0;
            if (code >= 400 && code < 500) return false;
            if (e.error == 'session_expired') return false;
            if (e.error == 'device_revoked') return false;
            if (e.error == 'hmac_required') return false;
            if (e.error == 'device_limit_reached') return false;
            if (e.error == 'quota_exceeded') return false;
            if (e.error == 'tt_provision_failed') return false;
            if (e.error is FormatException || e.error is TypeError) {
              return false;
            }
            if (code == 502 || code == 503) {
              // TrustTunnel hard failures must surface immediately (ADR 006).
              if (_apiErrorCode(e) == 'tt_provision_failed') {
                return false;
              }
            }
          }
          return true;
        },
        onRetry: (attempt, e) {
          _vpnLog('[VPN] fetchConfig retry $attempt after error: $e');
        },
      );
    } on DioException catch (e) {
      if (e.error == 'hmac_required') {
        // Lost local api_secret while the server still knows this install:
        // re-register with the SAME install id re-returns the secret (ADR 012).
        // Never rotate here — that would orphan the install.
        _vpnLog(
            '[VPN] hmac_required → heal register (same install), retry once');
        await ApiSecretStorage.instance.clear();
        ref.read(vpnConfigRepositoryProvider).clearCache();
        await ref.read(authProvider.notifier).retryBootstrap();
        final auth = ref.read(authProvider).valueOrNull;
        if (auth is! AuthStateAuthenticated) {
          rethrow;
        }
        return ref.read(vpnConfigRepositoryProvider).getConfig(
              forceRefresh: true,
              nodeId: apiNodeId == kRegionAutoId ? null : apiNodeId,
            );
      }
      if (e.error == 'device_revoked') {
        // The account owner revoked this install. Do NOT rotate + silently
        // mint a fresh anonymous account — the subscription stays on the old
        // one. Log out to Welcome, where restore is one tap away.
        _vpnLog(
            '[VPN] device_revoked → logout to Welcome (no silent register)');
        await SessionExpiredGate.onDeviceRevoked?.call();
      }
      rethrow;
    }
  }

  /// Friendly title from `/vpn/nodes` catalog (Auto pick or manual region).
  Future<String?> _labelForNodeId(
    String? nodeId, {
    List<VpnNode>? catalog,
  }) async {
    if (nodeId == null || nodeId.isEmpty || nodeId == kRegionAutoId) {
      return null;
    }
    try {
      final nodes = catalog ??
          await ref.read(vpnNodesRepositoryProvider).loadCachedNodes() ??
          await ref.read(vpnNodesRepositoryProvider).listNodes();
      final index = nodes.indexWhere((n) => n.id == nodeId);
      if (index < 0) return null;
      final place = await resolvePlaceForNode(nodes[index], index: index);
      return place.displayTitle(AppLocale.current.languageCode);
    } catch (_) {
      return null;
    }
  }

  Future<void> _runAutoProveLoop({int? gen}) async {
    if (gen != null && await _abortStaleConnect(gen)) return;
    final nodesRepo = ref.read(vpnNodesRepositoryProvider);
    final catalog = await nodesRepo.listNodes();
    if (gen != null && await _abortStaleConnect(gen)) return;
    final sub = ref.read(subscriptionStatusProvider).valueOrNull;
    final isPremium = sub?.unlocksPremium ?? false;
    String? lastWinner;
    try {
      lastWinner = await nodesRepo.getAutoLastWinnerId();
    } on StateError {
      lastWinner = null;
    }
    final pool = preferLastAutoWinner(
      autoPoolFor(catalog, isPremium: isPremium),
      lastWinner,
    );
    _lastAutoPoolIds = pool.map((n) => n.id).join(',');
    _vpnLog('[VPN] auto pool n=${pool.length} premium=$isPremium '
        'winner=$lastWinner ids=$_lastAutoPoolIds attempt=$_autoConnectAttempt');
    ProductLog.event('vpn.connect_attempt', {
      'mode': 'auto',
      'pool_ids': _lastAutoPoolIds,
      'premium': isPremium,
      'attempt': _autoConnectAttempt,
      'last_winner': lastWinner,
    });
    if (pool.isEmpty) {
      ProductLog.event('vpn.connect_fail', {
        'code': 'empty_pool',
        'reason': 'empty_pool',
        'attempt': _autoConnectAttempt,
      });
      state = const VpnError(
        message: 'empty_pool',
        code: 'empty_pool',
      );
      return;
    }
    final firstHint = _autoHintLabel(pool.first);
    state = VpnConnecting(
      progress: 0.55,
      hint: firstHint,
    );

    _autoMints.clear();
    _autoActiveNodeId = null;
    List<_MintAttempt> minted;
    try {
      minted = await Future.wait([
        for (final node in pool) _mintAutoNode(node, gen),
      ]);
    } on _AutoMintQuotaExceeded {
      ProductLog.event('vpn.connect_fail', {'code': 'quota_exceeded'});
      state = const VpnError(
        message: 'quota_exceeded',
        code: 'quota_exceeded',
      );
      return;
    }
    if (gen != null && await _abortStaleConnect(gen)) return;

    final payloads = <String>[];
    final skips = <AutoMintSkipKind>[];
    for (var i = 0; i < pool.length; i++) {
      final attempt = minted[i];
      final mint = attempt.mint;
      if (mint == null) {
        final skip = attempt.skip;
        if (skip != null) skips.add(skip);
        continue;
      }
      final node = pool[i];
      _autoMints[node.id] = mint;
      if (_autoMints.length == 1) {
        _applyAutoMint(node.id);
      }
      payloads.add(
        await VpnController.instance.buildStartParamsJson(
          mint.config,
          displayLabel: mint.label,
          catalogNodeId: node.id,
        ),
      );
    }
    if (payloads.isEmpty) {
      if (autoMintEmptyFailCode(skips) == kVpnApiUnreachableErrorCode) {
        await _onApiUnreachable();
      } else {
        await _onAutoPathIncompatible(reason: 'mint_empty');
      }
      return;
    }
    final started = await VpnController.instance.startAuto(payloads);
    if (!started) {
      ProductLog.event('vpn.connect_fail', {
        'code': 'start_auto_false',
        'pool_ids': _lastAutoPoolIds,
        'attempt': _autoConnectAttempt,
      });
      state = await _errorForStartFailure();
      return;
    }
    state = VpnConnecting(
      progress: 0.8,
      hint: firstHint,
    );
  }

  Future<_MintAttempt> _mintAutoNode(VpnNode node, int? gen) async {
    if (gen != null && await _abortStaleConnect(gen)) {
      return const _MintAttempt.skipped();
    }
    try {
      final cfg = await _autoMintRetryPolicy.execute(
        () => ref
            .read(vpnConfigRepositoryProvider)
            .getConfig(
              forceRefresh: true,
              nodeId: node.id,
            )
            .timeout(_autoMintTimeout),
        shouldRetry: (e) async {
          if (e is TimeoutException) return true;
          if (e is DioException) {
            final code = e.response?.statusCode ?? 0;
            if (e.error == 'quota_exceeded' ||
                _apiErrorCode(e) == 'quota_exceeded') {
              return false;
            }
            if (code >= 400 && code < 500) return false;
            if (e.error == 'tt_provision_failed' ||
                e.error == 'hy2_provision_failed') {
              return false;
            }
          }
          return e is! FormatException;
        },
      );
      if (gen != null && await _abortStaleConnect(gen)) {
        return const _MintAttempt.skipped();
      }
      final label = _autoHintLabel(node);
      ProductLog.event('vpn.mint', {
        'id': node.id,
        'active_core': cfg.activeCore.name,
        'protocol': node.protocol,
      });
      return _MintAttempt.ok(
        _AutoMint(
          config: cfg,
          label: label,
          protocol: node.protocol,
        ),
      );
    } on DioException catch (e) {
      if (e.error == 'quota_exceeded' || _apiErrorCode(e) == 'quota_exceeded') {
        throw _AutoMintQuotaExceeded();
      }
      ProductLog.event('vpn.mint', {
        'id': node.id,
        'skip': true,
        'code': e.error ?? _apiErrorCode(e) ?? e.response?.statusCode,
      });
      _vpnLog('[VPN] auto mint skip ${node.id}: $e', warn: true);
      return _MintAttempt.skipped(
        isControlPlaneTransportError(e)
            ? AutoMintSkipKind.connection
            : AutoMintSkipKind.other,
      );
    } catch (e) {
      ProductLog.event('vpn.mint', {
        'id': node.id,
        'skip': true,
        'code': e.runtimeType.toString(),
      });
      _vpnLog('[VPN] auto mint skip ${node.id}: $e', warn: true);
      return _MintAttempt.skipped(
        isControlPlaneTransportError(e)
            ? AutoMintSkipKind.connection
            : AutoMintSkipKind.other,
      );
    }
  }

  /// DNS/connect failed for every Auto candidate. Do not Wi-Fi-retry that
  /// as a data-plane path miss — the process bind is still the broken path.
  Future<void> _onApiUnreachable() async {
    ProductLog.event('vpn.connect_fail', {
      'code': kVpnApiUnreachableErrorCode,
      'reason': 'mint_empty',
      'pool_ids': _lastAutoPoolIds,
      'attempt': _autoConnectAttempt,
    });
    _endSessionWalk();
    _cancelConnectingWatchdog();
    state = const VpnError(
      message: kVpnApiUnreachableErrorCode,
      code: kVpnApiUnreachableErrorCode,
    );
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
    ProductLog.event('vpn.connect_fail', {
      'code': kVpnPathIncompatibleErrorCode,
      'reason': reason,
      'underlying': iface,
      'pool_ids': _lastAutoPoolIds,
      'attempt': _autoConnectAttempt,
    });
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

  /// Persist region and refresh cached config.
  ///
  /// Hot switch (already Connected/Connecting): mint **while TUN is up** so
  /// API `:8443` still routes (iOS RF hang without tunnel), then stop → idle →
  /// reconnect. Stay [VpnConnecting] — do not flash Disconnected mid-switch.
  Future<void> selectNode(String nodeId) async {
    final nodesRepo = ref.read(vpnNodesRepositoryProvider);
    final wasConnected = state is VpnConnected || state is VpnConnecting;
    final useAuto = nodeId == kRegionAutoId;
    if (useAuto) {
      await nodesRepo.setSelectedNodeId(kRegionAutoId);
    } else {
      await nodesRepo.setSelectedNodeId(nodeId);
    }
    ref.read(vpnConfigRepositoryProvider).clearCache();
    try {
      ref.read(betaUsageTrackerProvider).recordRegionChange();
    } on StateError {
      // Provider disposed in tests.
    }

    if (wasConnected) {
      state = const VpnConnecting(progress: 0.2);
      await runHotRegionSwitch(
        mint: () async {
          _config = await fetchConfig(nodeId: useAuto ? null : nodeId);
        },
        stopAndWaitIdle: () async {
          _reconnectTimer?.cancel();
          _cancelStatusSubscriptions();
          try {
            await VpnController.instance.stop(reason: 'region_switch');
          } catch (_) {
            // Best-effort before region switch.
          }
          // iOS Packet Tunnel: stop() must settle to idle before start, or the
          // late previous stopTunnel races the new start (false vpn_conflict).
          await waitUntilNativeIdle();
          await _clearConnectedSince();
          state = const VpnConnecting(progress: 0.5);
        },
        connectReuse: () => connect(reuseConfig: true),
      );
      return;
    }

    _config = await fetchConfig(nodeId: useAuto ? null : nodeId);
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
    if (_connectInFlight != null) return _connectInFlight!;
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

    // Allow retry after a stuck VpnConnecting (e.g. hung fetchConfig).
    try {
      ref.read(betaUsageTrackerProvider).recordConnectAttempt();
    } on StateError {
      // Provider disposed in tests.
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
        final imported = await Hy2ImportStore.instance.selected();
        if (await _abortStaleConnect(gen)) return;
        if (imported == null) {
          state = const VpnError(
            message: 'hy2_import_required',
            code: 'hy2_import_required',
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
        await VpnSessionMeta.clear();
        final profile = imported.hy2?.profile;
        final bool started;
        if (profile != null) {
          final dial = _dialGen == 0 ? ++_dialGen : _dialGen;
          _nativeGenFloor = _lastNativeGen;
          ProductLog.event('vpn.connect_attempt', {
            'profile': shown.title,
            'scheme': imported.scheme,
            'host': _profileHost,
            'sni': profile.sni,
          });
          final raw = await VpnController.instance.startHysteria(
            profile,
            displayLabel: shown.title,
          );
          started = raw && _dialGen == dial;
        } else if (defaultTargetPlatform == TargetPlatform.android) {
          final xrayJson = buildXraySocksConfig(imported);
          if (xrayJson == null) {
            state = const VpnError(
              message: 'share_unsupported',
              code: 'share_unsupported',
            );
            return;
          }
          started = await VpnController.instance.startXray(
            xrayJson,
            displayLabel: shown.title,
          );
        } else {
          state = const VpnError(
            message: 'share_ios_hy2_only',
            code: 'share_ios_hy2_only',
          );
          return;
        }
        if (await _abortStaleConnect(gen)) return;
        if (!started) {
          state = await _errorForStartFailure();
          return;
        }
        state = const VpnConnecting(progress: 0.8);
        return;
      }

      final nodesRepo = ref.read(vpnNodesRepositoryProvider);
      final stored = await nodesRepo.getSelectedNodeId();
      if (await _abortStaleConnect(gen)) return;
      final useAuto =
          stored == null || stored.isEmpty || stored == kRegionAutoId;

      if (useAuto) {
        await _runAutoProveLoop(gen: gen);
        return;
      }

      // 1. Config — reuse when selectNode already fetched for this switch.
      if (reuseConfig && _config != null) {
        _vpnLog('[VPN] connect: reuseConfig');
      } else {
        _vpnLog('[VPN] connect: fetchConfig…');
        _config = await fetchConfig();
        _vpnLog('[VPN] connect: fetchConfig ok');
      }
      if (await _abortStaleConnect(gen)) return;
      ProductLog.event('vpn.connect_attempt', {
        'mode': 'manual',
        'id': _config?.hysteriaProfile?.nodeId ?? _config?.nodeHost,
        'core': _config?.activeCore.name,
      });

      // 3. Start VpnService — Hy2 only (ADR 018).
      final wantsHysteria = _config!.isHysteriaSession ||
          _selectedNodeProtocol == kVpnNodeProtocolHysteria2;
      _vpnLog(
        '[VPN] active_core=${_config!.activeCore.name} '
        'node_id=${_config!.hysteriaProfile?.nodeId ?? _config!.nodeHost} '
        'protocol=$_selectedNodeProtocol',
      );
      if (wantsHysteria) {
        final hy = _config!.hysteriaProfile;
        if (hy == null) {
          state = const VpnError(
            message: 'hy2_provision_failed',
            code: 'hy2_provision_failed',
          );
          return;
        }
      } else {
        state = const VpnError(
          message: 'hy2_provision_failed',
          code: 'hy2_provision_failed',
        );
        return;
      }
      final started = await _retryPolicy.execute(
        () {
          return VpnController.instance.startHysteria(
            _config!.hysteriaProfile!,
            displayLabel: _displayLabel,
          );
        },
        shouldRetry: (e) async => e is! VpnControllerException,
        onRetry: (attempt, e) {
          _vpnLog('[VPN] start retry $attempt after error: $e');
        },
      );
      if (await _abortStaleConnect(gen)) return;
      if (!started) {
        ProductLog.event('vpn.connect_fail', {'code': 'start_false'});
        state = await _errorForStartFailure();
        return;
      }
      // EventChannel + connecting poll complete the session (ADR 014).
      if (await _abortStaleConnect(gen)) return;
      state = const VpnConnecting(progress: 0.8);
    } catch (e, st) {
      if (await _abortStaleConnect(gen)) return;
      _cancelConnectingWatchdog();
      _vpnLog('[VPN] connect failed: $e\n$st', warn: true);
      ProductLog.event('vpn.connect_fail', {
        'code': e is DioException
            ? (e.error ?? e.response?.statusCode)
            : e.runtimeType,
        'message': e.toString(),
      });
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
        if (e.error == 'provision_pending' ||
            _apiErrorCode(e) == 'provision_pending' ||
            code == 502 ||
            code == 503) {
          state = const VpnError(
            message: 'provision_pending',
            code: 'provision_pending',
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
      _vpnLog('[VPN] disconnect stop timeout: $e');
      if (wipeNativeSession) rethrow;
    } catch (e) {
      _vpnLog('[VPN] disconnect error: $e');
      if (wipeNativeSession) rethrow;
    } finally {
      _cancelDisconnectWatchdog();
      _cancelStatusSubscriptions();
      _autoReconnectArmed = false;
      _connectInFlight = null;
      final after = await VpnController.instance.getStatus();
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
    ProductLog.event('vpn.session_end', {
      'duration_s': seconds,
      'profile': current.serverName,
      'scheme': _sessionScheme(current.protocol),
      'host': _profileHost,
    });
    try {
      ref.read(betaUsageTrackerProvider).recordSessionSeconds(seconds);
    } on StateError {
      // Provider disposed in tests.
    }
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
    try {
      ref.read(betaUsageTrackerProvider).recordReconnect();
    } on StateError {
      // Provider disposed in tests.
    }
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
      onError: (e) {
        _vpnLog('[VPN] statusStream error: $e');
      },
    );
    _sessionSubscription ??= VpnController.instance.sessionStream.listen(
      _onSessionSnapshot,
      onError: (e) {
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
    final winnerId = snap.candidateId?.trim();
    if (!freeKeyClient && winnerId != null && winnerId.isNotEmpty) {
      _autoActiveNodeId = winnerId;
      _applyAutoMint(winnerId);
    }
    if (snap.isProving) {
      if (!freeKeyClient) {
        final proveId = snap.candidateId ?? '';
        if (proveId.isNotEmpty && proveId != _lastLoggedProveId) {
          _lastLoggedProveId = proveId;
          _lastProveSummary = 'id=$proveId proving';
          ProductLog.event('vpn.prove', {'id': proveId, 'ok': 'pending'});
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
        ProductLog.event('vpn.prove', {
          'id': proveId,
          'ok': true,
          'reason': snap.reason.name,
        });
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
      ProductLog.event('vpn.connect_fail', {
        'code': snap.reason.name,
        'detail': snap.detail,
        'underlying': snap.underlyingIface,
        'pool_ids': _lastAutoPoolIds,
        'attempt': _autoConnectAttempt,
      });
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
    final mintLabel = (winnerId != null && winnerId.isNotEmpty)
        ? _autoMints[winnerId]?.label.trim()
        : null;
    final label = (mintLabel != null && mintLabel.isNotEmpty)
        ? mintLabel
        : autoCandidateHintLabelFromId(winnerId);
    if (label == null || label.isEmpty) return;
    final current = state as VpnConnecting;
    state = VpnConnecting(
      progress: current.progress,
      hint: label,
    );
  }

  String _autoHintLabel(VpnNode node) => autoCandidateHintLabel(
        node,
        languageCode: AppLocale.current.languageCode,
      );

  String? autoCandidateHintLabelFromId(String? nodeId) {
    if (nodeId == null || nodeId.isEmpty) return null;
    final mint = _autoMints[nodeId];
    if (mint != null && mint.label.trim().isNotEmpty) return mint.label.trim();
    return null;
  }

  void _onNativeStatus(VpnNativeStatus nativeStatus) {
    switch (nativeStatus) {
      case VpnNativeStatus.connected:
        if (_suppressAutoReconnect) return;
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
        if (wasConnected) {
          _scheduleReconnect();
        }
      case VpnNativeStatus.error:
        if (_sessionOwnsUi) return;
        if (state is VpnError) return;
        final wasConnected = state is VpnConnected;
        final wasConnecting = state is VpnConnecting;
        if (wasConnected) _recordSessionEnd();
        unawaited(_clearConnectedSince());
        unawaited(
          _vpnErrorFromNative().then((err) {
            if (_sessionOwnsUi || state is VpnError) return;
            ProductLog.event('vpn.connect_fail', {
              'code': err.code,
              'message': err.message,
              'host': _profileHost,
            });
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
    _connectGeneration++;
    _activeConnectGen = null;
    _suppressAutoReconnect = true;
    _endSessionWalk();
    _sessionOwnsUi = false;
    _sessionProving = false;
    await _clearConnectedSince();
    final conflict = await VpnController.instance.queryVpnConflict();
    if (conflict.foreignAlwaysOn || conflict.foreignVpnActive) {
      _vpnLog('[VPN] connecting stuck — conflict CTA');
      state = await _vpnErrorFromConflict(conflict);
      return;
    }
    // iOS has no getVpnConflict — do not paint Android "another VPN" copy.
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
      _vpnLog('[VPN] reconnect skipped; native owns free client reason=$reason');
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

void _vpnLog(String message, {bool warn = false}) {
  debugPrint(message);
  if (warn) {
    AppLogBuffer.instance.warn(message);
  } else {
    AppLogBuffer.instance.info(message);
  }
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

final class _AutoMintQuotaExceeded implements Exception {}

final class _MintAttempt {
  const _MintAttempt.ok(this.mint) : skip = null;

  const _MintAttempt.skipped([this.skip]) : mint = null;

  final _AutoMint? mint;
  final AutoMintSkipKind? skip;
}

final class _AutoMint {
  const _AutoMint({
    required this.config,
    required this.label,
    required this.protocol,
  });

  final VpnConfig config;
  final String label;
  final String protocol;
}

final vpnProvider = NotifierProvider<VpnNotifier, VpnStatus>(
  VpnNotifier.new,
);
