import 'dart:async';

import 'package:flutter/services.dart';

import 'vpn_config.dart';
import 'vpn_service_config.dart';
import 'sing_box_runtime_config.dart';
import 'vpn_rule_sets.dart';
import 'vpn_session_meta.dart';

/// Контроллер VPN-сессии — мост между Flutter UI и Android VpnService.
///
/// Использует [MethodChannel] `teremok/vpn` для команд и [EventChannel]
/// `teremok/vpn/status` для live-обновлений статуса от нативного кода.
class VpnController {
  VpnController._();
  static final VpnController instance = VpnController._();

  static const _methodChannel = MethodChannel('teremok/vpn');
  static const _eventChannel = EventChannel('teremok/vpn/status');

  /// Таймаут на start (Шаг 16): 10 сек.
  static const Duration startTimeout = Duration(seconds: 10);

  /// Таймаут на stop (Шаг 16): 5 сек.
  static const Duration stopTimeout = Duration(seconds: 5);

  Stream<VpnNativeStatus>? _statusStream;

  /// Подключиться к VPN с переданным конфигом.
  ///
  /// Преобразует [VpnConfig] в [VpnServiceConfig] (с дефолтами для dev)
  /// и передаёт как JSON-строку в нативный код через MethodChannel.
  ///
  /// [displayLabel] — явная подпись региона/ноды (например после Авто-пика).
  Future<bool> start(VpnConfig config, {String? displayLabel}) async {
    try {
      final outbound = config.singBoxConfig.primaryOutbound;
      if (outbound == null) {
        throw VpnControllerException('sing-box config has no outbounds');
      }

      final serviceConfig = VpnServiceConfig.fromVpnConfig(
        config,
        displayLabel: displayLabel,
      );
      // Bundled .srs — never download from GitHub at connect time (RF blocks).
      Map<String, String> localRules = const {};
      var ruRulesLoaded = false;
      try {
        localRules = await prepareLocalRuleSetPaths();
        ruRulesLoaded = localRules.length == kRuleSetAssets.length;
      } catch (e) {
        // Unit tests lack path_provider; connect still works without RU split.
        // ignore: avoid_print
        print('[VPN] local rule-sets skipped: $e');
      }
      await VpnSessionMeta.saveConnectMeta(
        ruRulesLoaded: ruRulesLoaded,
        ruRuleTags: localRules.keys.toList(),
        expectedEgressHost: config.expectedEgressHost,
      );
      final singBoxConfigJson = buildRuntimeSingBoxJson(
        config: config,
        service: serviceConfig,
        localRulePaths: localRules,
      );
      final paramsJson = serviceConfig.toJsonStringWithSingBox(singBoxConfigJson);

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
      return result ?? false;
    } on TimeoutException catch (e) {
      throw VpnControllerException('start timeout: $e');
    } on PlatformException catch (e) {
      throw VpnControllerException('start failed: ${e.code} ${e.message}');
    }
  }

  /// Отключиться от VPN.
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

  /// Текущий статус (синхронный запрос к нативному коду).
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

  /// Последнее сообщение об ошибке от libbox/VpnService (если status == error).
  Future<String?> getLastError() async {
    try {
      return await _methodChannel.invokeMethod<String>('getLastError');
    } on PlatformException {
      return null;
    }
  }

  /// Last N lines of sing-box stderr log (Android libbox working dir).
  Future<String?> getSingBoxStderrTail({int maxLines = 30}) async {
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

  /// Underlying cellular/Wi‑Fi interface name while VPN is up (Android).
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

  /// Android Always-on "Block connections without VPN" — blocks excludeRoute.
  Future<bool> isLockdownEnabled() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('isLockdownEnabled');
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Android 13+: ask for POST_NOTIFICATIONS so VPN shade card is visible.
  Future<bool> requestNotificationPermission() async {
    try {
      final result =
          await _methodChannel.invokeMethod<bool>('requestNotificationPermission');
      return result ?? true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return true;
    }
  }

  /// Live-обновления статуса от нативного кода через EventChannel.
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
          // Если EventChannel не зарегистрирован (debug без сервиса) —
          // тихо проглатываем ошибку, статус можно узнать через getStatus().
          return VpnNativeStatus.unknown;
        });
    return _statusStream!;
  }

  /// Проверить/запросить VPN permission. На Android покажет системный диалог.
  ///
  /// Возвращает true если permission уже есть (или был только что выдан).
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

/// Статусы, возвращаемые нативным кодом через EventChannel `teremok/vpn/status`.
///
/// Имена совпадают со строковыми значениями в [VpnStatusBroadcaster] на Kotlin
/// (см. TeremokVpnService.kt).
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

class VpnControllerException implements Exception {
  VpnControllerException(this.message);
  final String message;

  @override
  String toString() => 'VpnControllerException: $message';
}