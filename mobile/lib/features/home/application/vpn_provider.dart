import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api_secret_storage.dart';
import '../../../core/install_id_storage.dart';
import '../../../core/retry_policy.dart';
import '../../auth/application/auth_provider.dart';
import '../../auth/application/auth_state.dart';
import '../../beta/application/beta_usage_tracker.dart';
import '../../vpn/data/node_auto_selector.dart';
import '../../vpn/data/node_display.dart';
import '../../vpn/data/vpn_config.dart';
import '../../vpn/data/vpn_config_repository.dart';
import '../../vpn/data/vpn_controller.dart';
import '../../vpn/data/vpn_node.dart';
import '../../vpn/data/vpn_nodes_repository.dart';
import '../../vpn/data/vpn_service_config.dart';
import '../../vpn/domain/vpn_connect_error.dart';
import '../../settings/data/auto_reconnect_prefs.dart';
import 'vpn_status.dart';

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

const _connectedSinceKey = 'vpn_connected_since_ms';

/// Home + analytics: another app holds Always-on / lockdown.
const kVpnConflictErrorCode = 'vpn_conflict';

/// VPN-контроллер. Шаг 16: retry/reconnect логика поверх VpnController + native.
class VpnNotifier extends Notifier<VpnStatus> {
  VpnConfig? _config;

  /// Label from catalog after Auto/manual pick (overrides generic host fallback).
  String? _displayLabel;

  /// Protocol of the catalog node chosen at fetchConfig / selectNode time
  /// (`kVpnNodeProtocolTrusttunnel` → start TrustTunnel core, ADR 006).
  String? _selectedNodeProtocol;

  /// Последний полученный конфиг. Доступен из UI для preview.
  VpnConfig? get config => _config;

  /// Friendly region label for the active egress hop (read-only Home card).
  String? get displayLabel => _displayLabel;

  StreamSubscription<VpnNativeStatus>? _statusSubscription;
  Timer? _reconnectTimer;
  Timer? _connectingWatchdog;
  Timer? _connectingPoll;
  Timer? _disconnectWatchdog;
  Future<void>? _syncInFlight;
  /// True while a connect() Future is in-flight (dedupe concurrent callers).
  Future<void>? _connectInFlight;
  bool _autoReconnectArmed = false;
  /// Set after intentional stop / self-revoke — blocks [_scheduleReconnect]
  /// and syncFromNative auto-reconnect until the next user [connect].
  bool _suppressAutoReconnect = false;

  void _cancelConnectingWatchdog() {
    _connectingWatchdog?.cancel();
    _connectingWatchdog = null;
    _connectingPoll?.cancel();
    _connectingPoll = null;
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
    // ignore: avoid_print
    print('[VPN] reconcileWithNative native=$native ui=$state');
    switch (native) {
      case VpnNativeStatus.connected:
        if (state is! VpnConnected) {
          try {
            _config ??= await fetchConfig();
          } catch (e) {
            // ignore: avoid_print
            print('[VPN] reconcile fetchConfig soft-fail: $e');
          }
          await _enterConnected(freshSession: state is VpnConnecting);
        }
      case VpnNativeStatus.connecting:
      case VpnNativeStatus.preparing:
        if (state is VpnDisconnected || state is VpnError) {
          state = const VpnConnecting(progress: 0.5);
          _armConnectingWatchdog();
        }
      case VpnNativeStatus.idle:
      case VpnNativeStatus.unknown:
        if (state is VpnConnecting && _connectInFlight == null) {
          await _clearConnectedSince();
          state = const VpnDisconnected();
        } else if (state is VpnConnected) {
          await _confirmIdleDrop();
        }
      case VpnNativeStatus.error:
        if (state is! VpnError) {
          state = await _vpnErrorFromNative();
        }
      case VpnNativeStatus.disconnecting:
        break;
      case VpnNativeStatus.revoked:
        if (state is VpnConnected || state is VpnConnecting) {
          await _clearConnectedSince();
          state = const VpnError(message: 'VPN was revoked by system');
        }
    }
  }

  /// Escape hatch: native can stick on preparing/connecting (Always-on race).
  /// Also polls every 1.5s so we don't wait the full timeout when already up.
  void _armConnectingWatchdog({Duration timeout = const Duration(seconds: 20)}) {
    _cancelConnectingWatchdog();
    _connectingPoll = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      unawaited(_pollConnectingNative());
    });
    _connectingWatchdog = Timer(timeout, () async {
      if (state is! VpnConnecting) return;
      final native = await VpnController.instance.getStatus();
      // ignore: avoid_print
      print('[VPN] connecting watchdog fired native=$native ui=$state');
      if (native == VpnNativeStatus.connected) {
        await _enterConnected(freshSession: true);
        return;
      }
      if (native == VpnNativeStatus.error) {
        state = await _vpnErrorFromNative();
        return;
      }
      // Stuck preparing/connecting/idle — force stop so UI can recover.
      try {
        await VpnController.instance.stop();
      } catch (_) {}
      await _clearConnectedSince();
      _autoReconnectArmed = false;
      _connectInFlight = null;
      state = const VpnError(
        message: 'Подключение зависло — нажмите ещё раз',
      );
    });
  }

  Future<void> _pollConnectingNative() async {
    if (state is! VpnConnecting) {
      _connectingPoll?.cancel();
      _connectingPoll = null;
      return;
    }
    final native = await VpnController.instance.getStatus();
    if (native == VpnNativeStatus.connected) {
      await _enterConnected(freshSession: true);
    }
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

  /// After prepare denial: foreign Always-on / lockdown → [vpn_conflict], else permission.
  Future<VpnError> _errorForPermissionFailure() async {
    final conflict = await VpnController.instance.queryVpnConflict();
    if (conflict.foreignAlwaysOn) {
      final label = conflict.appLabel?.trim();
      return VpnError(
        message: (label != null && label.isNotEmpty) ? label : 'vpn_conflict',
        code: kVpnConflictErrorCode,
      );
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
      final label = conflict.appLabel?.trim();
      return VpnError(
        message: (label != null && label.isNotEmpty) ? label : 'vpn_conflict',
        code: kVpnConflictErrorCode,
      );
    }
    final detail = await VpnController.instance.getLastError();
    if (detail != null &&
        detail.toLowerCase().contains('permission denied')) {
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
  }

  Future<void> _enterConnected({required bool freshSession}) async {
    _cancelConnectingWatchdog();
    if (state is VpnConnected && !freshSession) {
      return;
    }
    final config = _config;
    final serverName = config != null
        ? resolveVpnDisplayLabel(config, displayLabel: _displayLabel)
        : kVpnBrandSessionName;
    final protocol = config?.isTrustTunnelSession == true ||
            _selectedNodeProtocol == kVpnNodeProtocolTrusttunnel
        ? 'TRUSTTUNNEL'
        : friendlyProtocolLabel(
            config?.xrayProfile?.candidates.isNotEmpty == true
                ? config!.primaryCandidate.protocol
                : 'vless',
          );
    final since = await _resolveConnectedSince(freshSession: freshSession);
    state = VpnConnected(
      serverName: serverName,
      protocol: protocol,
      connectedSince: since,
    );
    if (freshSession) {
      try {
        ref.read(betaUsageTrackerProvider).recordConnectSuccess();
      } on StateError {
        // Provider disposed in tests.
      }
    }
  }

  @override
  VpnStatus build() {
    // Если пользователь разлогинился — сбрасываем VPN в Disconnected
    // и чистим кеш репозитория + подписку на статус.
    ref.listen<AsyncValue<AuthState>>(authProvider, (prev, next) {
      if (next.valueOrNull is! AuthStateAuthenticated) {
        _cleanupOnLogout();
      }
    });
    ref.onDispose(_cleanupOnLogout);
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
        // ignore: avoid_print
        print('[VPN] syncFromNative[$attempt] status=$native');
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
        if (state is VpnConnected) return;
        try {
          _config ??= await fetchConfig();
        } catch (e) {
          // ignore: avoid_print
          print('[VPN] syncFromNative fetchConfig soft-fail: $e');
        }
        await _enterConnected(freshSession: false);
        return;
      }
      if (native == VpnNativeStatus.connecting ||
          native == VpnNativeStatus.preparing) {
        state = const VpnConnecting(progress: 0.5);
        _armConnectingWatchdog();
        return;
      }
      if (native == VpnNativeStatus.error) {
        state = await _vpnErrorFromNative();
        return;
      }
      if (native == VpnNativeStatus.idle || native == VpnNativeStatus.unknown) {
        if (state is VpnConnected || state is VpnConnecting) {
          await _clearConnectedSince();
          state = const VpnDisconnected();
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
            // ignore: avoid_print
            print('[VPN] syncFromNative: auto-reconnect already in flight');
            return;
          }
          _autoReconnectArmed = true;
          // ignore: avoid_print
          print(
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
      // ignore: avoid_print
      print('[VPN] syncFromNative failed: $e');
    }
  }

  Future<void> _cleanupOnLogout() async {
    _cancelConnectingWatchdog();
    _cancelDisconnectWatchdog();
    if (state is! VpnDisconnected) {
      state = const VpnDisconnected();
    }
    _config = null;
    _displayLabel = null;
    _selectedNodeProtocol = null;
    _statusSubscription?.cancel();
    _statusSubscription = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _clearConnectedSince();
    try {
      ref.read(vpnConfigRepositoryProvider).clearCache();
    } on StateError {
      // ProviderContainer may already be disposed (unit tests).
    }
    try {
      await VpnController.instance.stop();
    } catch (_) {
      // Ignore — best-effort cleanup.
    }
  }

  /// Получить конфиг без подключения (для UI/preview).
  ///
  /// Retry на transient ошибках (5xx, network), без retry на 4xx.
  /// Respects persisted region selection; Auto → resolveNodeIdForConfig.
  Future<VpnConfig> fetchConfig({String? nodeId}) async {
    final nodesRepo = ref.read(vpnNodesRepositoryProvider);
    final stored = nodeId ?? await nodesRepo.getSelectedNodeId();
    final useAuto =
        stored == null || stored.isEmpty || stored == kRegionAutoId;
    if (useAuto) {
      await nodesRepo.setSelectedNodeId(kRegionAutoId);
    }
    _displayLabel = null;
    _selectedNodeProtocol = null;
    List<VpnNode>? catalog;
    String? apiNodeId;
    try {
      if (useAuto) {
        // Auto needs a live (or fallback) catalog to pick the best node.
        catalog = await nodesRepo.listNodes();
        apiNodeId = await resolveNodeIdForConfig(
          storedId: kRegionAutoId,
          catalog: catalog,
        );
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
      // ignore: avoid_print
      print('[VPN] selected node_id=$apiNodeId auto=$useAuto');
      if (apiNodeId != null) {
        for (final n in catalog) {
          if (n.id == apiNodeId) {
            _selectedNodeProtocol = n.protocol;
            break;
          }
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('[VPN] node pick failed, using default: $e');
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
          // ignore: avoid_print
          print('[VPN] fetchConfig retry $attempt after error: $e');
        },
      );
    } on DioException catch (e) {
      if (e.error == 'device_revoked' || e.error == 'hmac_required') {
        // ignore: avoid_print
        print(
          '[VPN] ${e.error} → rotate install + cold register, then retry once',
        );
        await InstallIdStorage.instance.rotate();
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
      return place.title;
    } catch (_) {
      return null;
    }
  }

  /// Persist region and refresh cached config (disconnect → fetch → reconnect).
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
      _reconnectTimer?.cancel();
      _statusSubscription?.cancel();
      _statusSubscription = null;
      try {
        await VpnController.instance.stop();
      } catch (_) {
        // Best-effort before region switch.
      }
      await _clearConnectedSince();
      state = const VpnDisconnected();
    }
    _config = await fetchConfig(nodeId: useAuto ? null : nodeId);
    if (wasConnected) {
      // Config already fetched above — skip a second /vpn/config + nodes round-trip.
      await connect(reuseConfig: true);
    }
  }

  /// Explicit stop → start so route-mode / site prefs enter the next runtime config.
  Future<bool> reconnectToApplyRouting() async {
    final wasConnected = state is VpnConnected || state is VpnConnecting;
    if (!wasConnected) {
      await connect(forceRestart: true);
      return state is VpnConnected;
    }
    _reconnectTimer?.cancel();
    _statusSubscription?.cancel();
    _statusSubscription = null;
    try {
      await VpnController.instance.stop();
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
  }) async {
    // Deduplicate concurrent connect() (auto-reconnect + nest tap).
    _suppressAutoReconnect = false;
    if (_connectInFlight != null) return _connectInFlight!;
    if (!forceRestart && state is VpnConnected) return;

    _connectInFlight = _connectBody(
      forceRestart: forceRestart,
      reuseConfig: reuseConfig,
    ).whenComplete(() {
      _connectInFlight = null;
      _autoReconnectArmed = false;
    });
    return _connectInFlight!;
  }

  Future<void> _connectBody({
    bool forceRestart = false,
    bool reuseConfig = false,
  }) async {
    // Already up in the system tray (UI lost state after Activity recreate).
    final existing = await VpnController.instance.getStatus();
    if (!forceRestart && existing == VpnNativeStatus.connected) {
      await _syncFromNative();
      return;
    }
    if (forceRestart && existing == VpnNativeStatus.connected) {
      try {
        await VpnController.instance.stop();
      } catch (_) {}
    }

// Allow retry after a stuck VpnConnecting (e.g. hung fetchConfig).
    try {
      ref.read(betaUsageTrackerProvider).recordConnectAttempt();
    } on StateError {
      // Provider disposed in tests.
    }

    state = const VpnConnecting(progress: 0.0);
    _armConnectingWatchdog(timeout: const Duration(seconds: 45));

    try {
      // 1. Config — reuse when selectNode already fetched for this switch.
      if (reuseConfig && _config != null) {
        // ignore: avoid_print
        print('[VPN] connect: reuseConfig');
      } else {
        // ignore: avoid_print
        print('[VPN] connect: fetchConfig…');
        _config = await fetchConfig();
        // ignore: avoid_print
        print('[VPN] connect: fetchConfig ok');
      }
      state = const VpnConnecting(progress: 0.3);

      // 2. Проверяем permission (на Android открывает системный диалог)
      final hasPermission = await VpnController.instance.requestPermission();
      if (!hasPermission) {
        state = await _errorForPermissionFailure();
        return;
      }
      // Android 13+: without this the Amnezia-style VPN card stays hidden.
      await VpnController.instance.requestNotificationPermission();
      state = const VpnConnecting(progress: 0.5);

      // 3. Start VpnService — core from active_core (ADR 006), never silent Xray
      // fallback when the catalog/session is TrustTunnel.
      final wantsTrustTunnel = _config!.isTrustTunnelSession ||
          _selectedNodeProtocol == kVpnNodeProtocolTrusttunnel;
      // ignore: avoid_print
      print(
        '[VPN] active_core=${_config!.activeCore.name} '
        'node_id=${_config!.trusttunnelProfile?.nodeId ?? _config!.nodeHost} '
        'protocol=$_selectedNodeProtocol',
      );
      if (wantsTrustTunnel) {
        final tt = _config!.trusttunnelProfile;
        if (tt == null) {
          state = const VpnError(
            message: 'tt_provision_failed',
            code: 'tt_provision_failed',
          );
          return;
        }
      }
      final started = await _retryPolicy.execute(
        () => wantsTrustTunnel
            ? VpnController.instance.startTrustTunnel(
                _config!.trusttunnelProfile!,
                displayLabel: _displayLabel,
              )
            : VpnController.instance.start(
                _config!,
                displayLabel: _displayLabel,
              ),
        shouldRetry: (e) async => e is! VpnControllerException,
        onRetry: (attempt, e) {
          // ignore: avoid_print
          print('[VPN] start retry $attempt after error: $e');
        },
      );
      if (!started) {
        state = await _errorForStartFailure();
        return;
      }
      state = const VpnConnecting(progress: 0.8);

      // 4. Ждём connected/error (poll + EventChannel), до 15 с
      const pollInterval = Duration(milliseconds: 250);
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (state is VpnConnecting && DateTime.now().isBefore(deadline)) {
        final nativeStatus = await VpnController.instance.getStatus();
        if (nativeStatus == VpnNativeStatus.connected) {
          await _enterConnected(freshSession: true);
          return;
        }
        if (nativeStatus == VpnNativeStatus.error) {
          state = await _vpnErrorFromNative();
          return;
        }
        if (nativeStatus == VpnNativeStatus.idle) {
          final detail = await VpnController.instance.getLastError();
          if (detail != null && detail.isNotEmpty) {
            state = vpnErrorFromNativeDetail(detail);
            return;
          }
        }
        await Future<void>.delayed(pollInterval);
      }
      if (state is VpnConnecting) {
        _cancelConnectingWatchdog();
        state = const VpnError(
          message: 'VPN connection timeout',
        );
      }
    } catch (e, st) {
      _cancelConnectingWatchdog();
      // ignore: avoid_print
      print('[VPN] connect failed: $e\n$st');
      if (e is DioException) {
        final code = e.response?.statusCode ?? 0;
        if (e.error == 'device_limit_reached') {
          state = const VpnError(
            message: 'device_limit_reached',
            code: 'device_limit_reached',
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
            message: 'Сессия истекла — войдите снова',
          );
          return;
        }
        if (e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.connectionTimeout) {
          state = const VpnError(
            message: 'Нет связи с сервером — проверьте интернет',
          );
          return;
        }
      }
      state = VpnError(
        message: 'Connect failed: ${e is VpnControllerException ? e.message : e}',
      );
    } finally {
      if (state is! VpnConnecting) {
        _cancelConnectingWatchdog();
      }
    }
  }

  /// Call from Home [AppLifecycleState.resumed] (sync native status).
  Future<void> onAppResumed() async {
    await syncFromNative();
  }

  /// Block auto-reconnect (device self-revoke / intentional stop side-effects).
  void suppressAutoReconnect() {
    _suppressAutoReconnect = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _autoReconnectArmed = false;
  }

  Future<void> disconnect() async {
    _cancelConnectingWatchdog();
    _reconnectTimer?.cancel();
    _suppressAutoReconnect = true;
    // Always allow cancel while UI shows connecting (incl. stuck preparing).
    final native = await VpnController.instance.getStatus();
    final uiBusy = state is VpnConnected || state is VpnConnecting;
    final nativeBusy = native == VpnNativeStatus.connected ||
        native == VpnNativeStatus.connecting ||
        native == VpnNativeStatus.preparing;
    if (!uiBusy && !nativeBusy) {
      state = const VpnDisconnected();
      return;
    }
    _recordSessionEnd();
    if (state is VpnConnecting || state is VpnConnected) {
      state = const VpnConnecting(progress: 0.5); // disconnecting affordance
    }

    // If stop() hangs, don't leave Nest spinning forever.
    _cancelDisconnectWatchdog();
    _disconnectWatchdog = Timer(const Duration(seconds: 10), () async {
      // ignore: avoid_print
      print('[VPN] disconnect watchdog fired ui=$state');
      _connectInFlight = null;
      final still = await VpnController.instance.getStatus();
      if (still == VpnNativeStatus.connected) {
        await _enterConnected(freshSession: false);
      } else if (state is VpnConnecting) {
        await _clearConnectedSince();
        state = const VpnDisconnected();
      }
    });

    try {
      await VpnController.instance.stop().timeout(const Duration(seconds: 10));
    } on TimeoutException catch (e) {
      // ignore: avoid_print
      print('[VPN] disconnect stop timeout: $e');
    } catch (e) {
      // ignore: avoid_print
      print('[VPN] disconnect error: $e');
    } finally {
      _cancelDisconnectWatchdog();
      _statusSubscription?.cancel();
      _statusSubscription = null;
      _autoReconnectArmed = false;
      _connectInFlight = null;
      final after = await VpnController.instance.getStatus();
      if (after == VpnNativeStatus.connected) {
        // stop did not tear down — stay honest with native.
        _subscribeToStatus();
        await _enterConnected(freshSession: false);
      } else {
        await _clearConnectedSince();
        _subscribeToStatus();
        state = const VpnDisconnected();
      }
    }
  }

void _recordSessionEnd() {
    final current = state;
    if (current is! VpnConnected) return;
    final seconds =
        DateTime.now().difference(current.connectedSince).inSeconds;
    try {
      ref.read(betaUsageTrackerProvider).recordSessionSeconds(seconds);
    } on StateError {
      // Provider disposed in tests.
    }
  }

  /// Попытка автоматического переподключения через 5 сек (если включено в Settings).
  void _scheduleReconnect() {
    if (_suppressAutoReconnect) {
      // ignore: avoid_print
      print('[VPN] auto-reconnect suppressed (intentional stop/revoke)');
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
        // ignore: avoid_print
        print('[VPN] auto-reconnect skipped (disabled in Settings)');
        return;
      }
      if (state is VpnConnected || state is VpnConnecting) return;
      // ignore: avoid_print
      print('[VPN] attempting auto-reconnect...');
      await connect();
    });
  }

  void _subscribeToStatus() {
    if (_statusSubscription != null) return;
    _statusSubscription = VpnController.instance.statusStream.listen(
      _onNativeStatus,
      onError: (e) {
        // ignore: avoid_print
        print('[VPN] statusStream error: $e');
      },
    );
  }

  void _onNativeStatus(VpnNativeStatus nativeStatus) {
    switch (nativeStatus) {
      case VpnNativeStatus.connected:
        if (state is VpnConnected) return;
        // Coming from Connecting → new session; from elsewhere → restore stamp.
        final fresh = state is VpnConnecting;
        unawaited(_enterConnected(freshSession: fresh));
      case VpnNativeStatus.disconnecting:
        // Intentional stop in progress — UI already moving to disconnected.
        break;
      case VpnNativeStatus.idle:
        // Ignore idle while we still believe we're connected until getStatus
        // confirms (Always-on onCreate used to emit idle spuriously).
        if (state is VpnConnected) {
unawaited(_confirmIdleDrop());
        }
      case VpnNativeStatus.revoked:
        // VPN отозван системой (например, юзер переключил VPN в Settings).
        final wasConnected = state is VpnConnected;
        if (wasConnected) _recordSessionEnd();
        unawaited(_clearConnectedSince());
        state = const VpnError(message: 'VPN was revoked by system');
        if (wasConnected) {
          _scheduleReconnect();
        }
      case VpnNativeStatus.error:
        final wasConnected = state is VpnConnected;
        if (wasConnected) _recordSessionEnd();
        unawaited(_clearConnectedSince());
        unawaited(
          _vpnErrorFromNative().then((err) {
            state = err;
          }),
        );
        if (wasConnected) {
          _scheduleReconnect();
        }
      case VpnNativeStatus.unknown:
      case VpnNativeStatus.preparing:
      case VpnNativeStatus.connecting:
        if (state is VpnDisconnected || state is VpnError) {
          state = const VpnConnecting(progress: 0.5);
          _armConnectingWatchdog();
        }
    }
  }

  /// Don't flip UI to disconnected on a single idle event — re-check native.
  Future<void> _confirmIdleDrop() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
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
      state = const VpnDisconnected();
    }
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

final vpnProvider = NotifierProvider<VpnNotifier, VpnStatus>(
  VpnNotifier.new,
);
