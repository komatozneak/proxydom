import 'dart:async';

import 'package:flutter/services.dart';

import 'vpn_config.dart';

/// Контроллер VPN-сессии — мост между Flutter UI и Android VpnService.
///
/// Использует [MethodChannel] `teremok/vpn` для команд и [EventChannel]
/// `teremok/vpn/status` для live-обновлений статуса от нативного кода.
class VpnController {
  VpnController._();
  static final VpnController instance = VpnController._();

  static const _methodChannel = MethodChannel('teremok/vpn');
  static const _eventChannel = EventChannel('teremok/vpn/status');

  Stream<VpnNativeStatus>? _statusStream;

  /// Подключиться к VPN с переданным конфигом.
  ///
  /// На Android-стороне это вызовет ACTION_START в TeremokVpnService.
  /// Возвращает true если команда успешно отправлена (НЕ значит что VPN
  /// поднялся — реальное состояние придёт через [statusStream]).
  Future<bool> start(VpnConfig config) async {
    try {
      final primaryOutbound = config.singBoxConfig.primaryOutbound;
      if (primaryOutbound == null) {
        throw PlatformException(
          code: 'NO_OUTBOUND',
          message: 'sing-box config has no outbounds',
        );
      }

      final result = await _methodChannel.invokeMethod<bool>('start', {
        'username': config.username,
        'protocol': primaryOutbound.type,
        'server': primaryOutbound.server,
        'serverPort': primaryOutbound.serverPort,
        'uuid': primaryOutbound.uuid,
        'flow': primaryOutbound.flow,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      throw VpnControllerException('start failed: ${e.code} ${e.message}');
    }
  }

  /// Отключиться от VPN.
  Future<bool> stop() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('stop');
      return result ?? false;
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