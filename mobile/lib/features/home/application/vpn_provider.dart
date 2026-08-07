import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../settings/data/vpn_route_mode.dart';

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
import '../../settings/data/auto_reconnect_prefs.dart';
import 'vpn_status.dart';

/// Singleton-репозиторий для VPN-конфига.
final vpnConfigRepositoryProvider = Provider<VpnConfigRepository>(
  (ref) => VpnConfigRepository(),
);

final vpnNodesRepositoryProvider = Provider<VpnNodesRepository>(
  (ref) => VpnNodesRepository(),
);

/// Retry policy для VPN-операций (максимум 3 попытки).
final _retryPolicy = RetryPolicy(
  maxAttempts: 3,
  initialDelay: const Duration(milliseconds: 500),
  maxDelay: const Duration(seconds: 3),
);

const _connectedSinceKey = 'vpn_connected_since_ms';

/// VPN-контроллер. Шаг 16: retry/reconnect логика поверх VpnController + native.
class VpnNotifier extends Notifier<VpnStatus> {
  VpnConfig? _config;

  /// Label from catalog after Auto/manual pick (overrides generic host fallback).
  String? _displayLabel;

  /// Последний полученный конфиг. Доступен из UI для preview.
  VpnConfig? get config => _config;

  /// Friendly region label for the active egress hop (read-only Home card).
  String? get displayLabel => _displayLabel;

  StreamSubscription<VpnNativeStatus>? _statusSubscription;
  Timer? _reconnectTimer;
  Timer? _connectingWatchdog;
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
  }

  /// Escape hatch: native can stick on preparing/connecting (Always-on race).
  void _armConnectingWatchdog({Duration timeout = const Duration(seconds: 20)}) {
    _cancelConnectingWatchdog();
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
        state = VpnError(message: await _nativeErrorMessage());
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

  Future<String> _nativeErrorMessage() async {
    final detail = await VpnController.instance.getLastError();
    if (detail != null && detail.isNotEmpty) {
      return 'libbox: $detail';
    }
    return 'Native VPN error';
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
    final protocol = friendlyProtocolLabel(
      config?.singBoxConfig.primaryOutbound?.type,
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
        state = VpnError(message: await _nativeErrorMessage());
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
    if (state is! VpnDisconnected) {
      state = const VpnDisconnected();
    }
    _config = null;
    _displayLabel = null;
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
  /// Location picker removed: always Auto → urltest among egress_candidates.
  Future<VpnConfig> fetchConfig({String? nodeId}) async {
    final nodesRepo = ref.read(vpnNodesRepositoryProvider);
    await nodesRepo.setSelectedNodeId(kRegionAutoId);
    _displayLabel = null;
    List<VpnNode>? catalog;
    String? apiNodeId;
    try {
      catalog = await nodesRepo.listNodes();
      apiNodeId = await resolveNodeIdForConfig(
        storedId: kRegionAutoId,
        catalog: catalog,
      );
      // ignore: avoid_print
      print('[VPN] auto selected node_id=$apiNodeId');
    } catch (e) {
      // ignore: avoid_print
      print('[VPN] auto pick failed, using default: $e');
      apiNodeId = null;
    }

    _displayLabel = await _labelForNodeId(apiNodeId, catalog: catalog);

    try {
      return await _retryPolicy.execute(
        () => ref.read(vpnConfigRepositoryProvider).getConfig(
              forceRefresh: true,
              // Prefer Auto probe; backend returns full egress_candidates for urltest.
              nodeId: apiNodeId == kRegionAutoId ? null : apiNodeId,
            ),
        shouldRetry: (e) async {
          if (e is DioException) {
            // Не повторяем 4xx — авторизация/клиент; type может быть unknown.
            final code = e.response?.statusCode ?? 0;
            if (code >= 400 && code < 500) return false;
            if (e.error == 'session_expired') return false;
            if (e.error == 'device_revoked') return false;
            if (e.error == 'device_limit_reached') return false;
          }
          return true;
        },
        onRetry: (attempt, e) {
          // ignore: avoid_print
          print('[VPN] fetchConfig retry $attempt after error: $e');
        },
      );
    } on DioException catch (e) {
      if (e.error == 'device_revoked') {
        // ignore: avoid_print
        print('[VPN] device_revoked → rotate install id and retry once');
        await InstallIdStorage.instance.rotate();
        ref.read(vpnConfigRepositoryProvider).clearCache();
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
      final nodes = catalog ?? await ref.read(vpnNodesRepositoryProvider).listNodes();
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
      await connect();
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

  Future<void> connect({bool forceRestart = false}) async {
    // Deduplicate concurrent connect() (auto-reconnect + nest tap).
    _suppressAutoReconnect = false;
    if (_connectInFlight != null) return _connectInFlight!;
    if (!forceRestart && state is VpnConnected) return;

    _connectInFlight = _connectBody(forceRestart: forceRestart).whenComplete(() {
      _connectInFlight = null;
      _autoReconnectArmed = false;
    });
    return _connectInFlight!;
  }

  Future<void> _connectBody({bool forceRestart = false}) async {
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
      // 1. Получаем конфиг с retry
      // ignore: avoid_print
      print('[VPN] connect: fetchConfig…');
      _config = await fetchConfig();
      // ignore: avoid_print
      print('[VPN] connect: fetchConfig ok');
      state = const VpnConnecting(progress: 0.3);

      // 2. Проверяем permission (на Android открывает системный диалог)
      final hasPermission = await VpnController.instance.requestPermission();
      if (!hasPermission) {
        state = const VpnError(message: 'VPN permission denied');
        return;
      }
      // Android 13+: without this the Amnezia-style VPN card stays hidden.
      await VpnController.instance.requestNotificationPermission();
      state = const VpnConnecting(progress: 0.5);

      // 3. Стартуем VpnService (через MethodChannel) с retry на transient
      final started = await _retryPolicy.execute(
        () => VpnController.instance.start(
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
        state = const VpnError(message: 'Failed to start VPN service');
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
          state = VpnError(message: await _nativeErrorMessage());
          return;
        }
        if (nativeStatus == VpnNativeStatus.idle) {
          final detail = await VpnController.instance.getLastError();
          if (detail != null && detail.isNotEmpty) {
            state = VpnError(message: 'libbox: $detail');
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

    try {
      await VpnController.instance.stop();
    } catch (e) {
      // ignore: avoid_print
      print('[VPN] disconnect error: $e');
    } finally {
      _statusSubscription?.cancel();
      _statusSubscription = null;
      await _clearConnectedSince();
      _autoReconnectArmed = false;
      _connectInFlight = null;
      _subscribeToStatus();
      state = const VpnDisconnected();
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
          _nativeErrorMessage().then((msg) {
            state = VpnError(message: msg);
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

final vpnProvider = NotifierProvider<VpnNotifier, VpnStatus>(
  VpnNotifier.new,
);
