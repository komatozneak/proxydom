import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/retry_policy.dart';
import '../../auth/application/auth_provider.dart';
import '../../auth/application/auth_state.dart';
import '../../vpn/data/vpn_config.dart';
import '../../vpn/data/vpn_config_repository.dart';
import '../../vpn/data/vpn_controller.dart';
import '../../vpn/data/vpn_nodes_repository.dart';
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

/// VPN-контроллер. Шаг 16: retry/reconnect логика поверх VpnController + native.
class VpnNotifier extends Notifier<VpnStatus> {
  VpnConfig? _config;

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
    return const VpnDisconnected();
  }

  Future<void> _cleanupOnLogout() async {
    if (state is! VpnDisconnected) {
      state = const VpnDisconnected();
    }
    _config = null;
    _statusSubscription?.cancel();
    _statusSubscription = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
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
  Future<VpnConfig> fetchConfig({String? nodeId}) async {
    final nodesRepo = ref.read(vpnNodesRepositoryProvider);
    final selected = nodeId ?? await nodesRepo.getSelectedNodeId();
    return _retryPolicy.execute(
      () => ref.read(vpnConfigRepositoryProvider).getConfig(
            forceRefresh: nodeId != null,
            nodeId: selected,
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

  /// Persist region and refresh cached config (disconnect → fetch → reconnect).
  Future<void> selectNode(String nodeId) async {
    final nodesRepo = ref.read(vpnNodesRepositoryProvider);
    final wasConnected = state is VpnConnected || state is VpnConnecting;
    await nodesRepo.setSelectedNodeId(nodeId);
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
      state = const VpnDisconnected();
    }
    _config = await fetchConfig(nodeId: nodeId);
    if (wasConnected) {
      await connect();
    }
  }

  Future<void> connect() async {
    if (state is VpnConnecting || state is VpnConnected) return;
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
      state = const VpnConnecting(progress: 0.5);

      // Подписка до start — иначе пропускаем connected из EventChannel.
      _subscribeToStatus();

      // 3. Стартуем VpnService (через MethodChannel) с retry на transient
      final started = await _retryPolicy.execute(
        () => VpnController.instance.start(_config!),
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
          final serverName = _config?.username ?? 'unknown';
          final protocol =
              _config?.singBoxConfig.primaryOutbound?.type ?? 'unknown';
          state = VpnConnected(
            serverName: serverName,
            protocol: protocol,
            connectedSince: DateTime.now(),
          );
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
    if (state is! VpnConnected) return;
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
        final serverName = _config?.username ?? 'unknown';
        final protocol =
            _config?.singBoxConfig.primaryOutbound?.type ?? 'unknown';
        state = VpnConnected(
          serverName: serverName,
          protocol: protocol,
          connectedSince: DateTime.now(),
        );
      case VpnNativeStatus.disconnecting:
      case VpnNativeStatus.idle:
        if (state is VpnConnected) {
          state = const VpnDisconnected();
        }
      case VpnNativeStatus.revoked:
        // VPN отозван системой (например, юзер переключил VPN в Settings).
        final wasConnected = state is VpnConnected;
        state = const VpnError(message: 'VPN was revoked by system');
        if (wasConnected) {
          _scheduleReconnect();
        }
      case VpnNativeStatus.error:
        final wasConnected = state is VpnConnected;
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