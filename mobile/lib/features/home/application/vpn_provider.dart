import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/retry_policy.dart';
import '../../auth/application/auth_provider.dart';
import '../../auth/application/auth_state.dart';
import '../../vpn/data/node_auto_selector.dart';
import '../../vpn/data/node_display.dart';
import '../../vpn/data/vpn_config.dart';
import '../../vpn/data/vpn_config_repository.dart';
import '../../vpn/data/vpn_controller.dart';
import '../../vpn/data/vpn_node.dart';
import '../../vpn/data/vpn_nodes_repository.dart';
import '../../vpn/data/vpn_service_config.dart';
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

  StreamSubscription<VpnNativeStatus>? _statusSubscription;
  Timer? _reconnectTimer;

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
    // Dart UI restarts independently of VpnService — sync tray/native status.
    Future.microtask(_syncFromNative);
    return const VpnDisconnected();
  }

  /// Align UI with native VpnService after cold start / Activity recreate.
  Future<void> syncFromNative() => _syncFromNative();

  Future<void> _syncFromNative() async {
    try {
      final native = await VpnController.instance.getStatus();
      // ignore: avoid_print
      print('[VPN] syncFromNative status=$native');
      if (native == VpnNativeStatus.connected) {
        if (state is VpnConnected) return;
        _config ??= await fetchConfig();
        _subscribeToStatus();
        await _enterConnected(freshSession: false);
        return;
      }
      if (native == VpnNativeStatus.connecting ||
          native == VpnNativeStatus.preparing) {
        _subscribeToStatus();
        state = const VpnConnecting(progress: 0.5);
        return;
      }
      if (native == VpnNativeStatus.error) {
        state = VpnError(message: await _nativeErrorMessage());
      }
      if (native == VpnNativeStatus.idle || native == VpnNativeStatus.unknown) {
        await _clearConnectedSince();
      }
    } catch (e) {
      // ignore: avoid_print
      print('[VPN] syncFromNative failed: $e');
    }
  }

  Future<void> _cleanupOnLogout() async {
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
  /// When stored region is [kRegionAutoId], probes online nodes and picks fastest.
  Future<VpnConfig> fetchConfig({String? nodeId}) async {
    final nodesRepo = ref.read(vpnNodesRepositoryProvider);
    String? selected = nodeId ?? await nodesRepo.getSelectedNodeId();
    if (selected == null || selected.isEmpty) {
      selected = kRegionAutoId;
    }

    String? apiNodeId = selected;
    _displayLabel = null;
    List<VpnNode>? catalog;
    if (selected == kRegionAutoId) {
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
    }

    _displayLabel = await _labelForNodeId(apiNodeId, catalog: catalog);

    return _retryPolicy.execute(
      () => ref.read(vpnConfigRepositoryProvider).getConfig(
            forceRefresh: nodeId != null,
            nodeId: apiNodeId == kRegionAutoId ? null : apiNodeId,
          ),
      shouldRetry: (e) async {
        if (e is DioException) {
          // Не повторяем 4xx — это проблема авторизации/клиента, бессмысленно.
          final code = e.response?.statusCode ?? 0;
          if (e.type == DioExceptionType.badResponse && code < 500) {
            return false;
          }
        }
        return true;
      },
      onRetry: (attempt, e) {
        // ignore: avoid_print
        print('[VPN] fetchConfig retry $attempt after error: $e');
      },
    );
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
      return placeForNode(nodes[index], index: index).title;
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

  Future<void> connect() async {
    if (state is VpnConnecting || state is VpnConnected) return;

    // Already up in the system tray (UI lost state after Activity recreate).
    final existing = await VpnController.instance.getStatus();
    if (existing == VpnNativeStatus.connected) {
      await _syncFromNative();
      return;
    }

    state = const VpnConnecting(progress: 0.0);

    try {
      // 1. Получаем конфиг с retry
      _config = await fetchConfig();
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

      // Подписка до start — иначе пропускаем connected из EventChannel.
      _subscribeToStatus();

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
        state = const VpnError(
          message: 'VPN connection timeout',
        );
      }
    } catch (e, st) {
      // ignore: avoid_print
      print('[VPN] connect failed: $e\n$st');
      state = VpnError(
        message: 'Connect failed: ${e is VpnControllerException ? e.message : e}',
      );
    }
  }

  Future<void> disconnect() async {
    // Allow stop even if UI thought we were disconnected (native still up).
    final native = await VpnController.instance.getStatus();
    if (state is! VpnConnected &&
        native != VpnNativeStatus.connected &&
        native != VpnNativeStatus.connecting) {
      return;
    }
    state = const VpnConnecting(progress: 0.5); // reuse как "disconnecting"
    _reconnectTimer?.cancel();

    try {
      // Таймаут на disconnect — 5 сек (через VpnController.timeout)
      await VpnController.instance.stop();
    } catch (e) {
      // ignore: avoid_print
      print('[VPN] disconnect error: $e');
    } finally {
      _statusSubscription?.cancel();
      _statusSubscription = null;
      await _clearConnectedSince();
      state = const VpnDisconnected();
    }
  }

  /// Попытка автоматического переподключения через 5 сек.
  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      // ignore: avoid_print
      print('[VPN] attempting auto-reconnect...');
      connect();
    });
  }

  void _subscribeToStatus() {
    _statusSubscription?.cancel();
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
      case VpnNativeStatus.idle:
        if (state is VpnConnected) {
          unawaited(_clearConnectedSince());
          state = const VpnDisconnected();
        }
      case VpnNativeStatus.revoked:
        // VPN отозван системой (например, юзер переключил VPN в Settings).
        final wasConnected = state is VpnConnected;
        unawaited(_clearConnectedSince());
        state = const VpnError(message: 'VPN was revoked by system');
        if (wasConnected) {
          _scheduleReconnect();
        }
      case VpnNativeStatus.error:
        final wasConnected = state is VpnConnected;
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
        // Промежуточные состояния — оставляем текущий state.
        break;
    }
  }
}

final vpnProvider = NotifierProvider<VpnNotifier, VpnStatus>(
  VpnNotifier.new,
);
