import 'dart:async';

import 'package:flutter/services.dart';

import 'vpn_config.dart';
import 'vpn_config_constructor.dart';
import 'vpn_route_policy.dart';
import 'vpn_rule_sets.dart';
import 'vpn_service_config.dart';
import 'vpn_session_inputs.dart';
import 'vpn_session_meta.dart';
import '../../settings/data/split_tunnel_prefs.dart';
import '../../settings/data/vpn_route_mode.dart';

/// Контроллер VPN-сессии — мост между Flutter UI и Android VpnService.
///
/// Использует [MethodChannel] `teremok/vpn` для команд и [EventChannel]
/// `teremok/vpn/status` для live-обновлений статуса от нативного кода.
class VpnController {
  VpnController._();
  static final VpnController instance = VpnController._();

  static const _methodChannel = MethodChannel('teremok/vpn');
  static const _eventChannel = EventChannel('teremok/vpn/status');
  static const _trafficEventChannel = EventChannel('teremok/vpn/traffic');
  static const _pingEventChannel = EventChannel('teremok/vpn/ping');

  /// Таймаут на start (Шаг 16): 10 сек.
  static const Duration startTimeout = Duration(seconds: 10);

  /// Таймаут на stop (Шаг 16): 5 сек.
  static const Duration stopTimeout = Duration(seconds: 5);

  Stream<VpnNativeStatus>? _statusStream;
  Stream<VpnTrafficStats>? _trafficStream;
  Stream<int?>? _pingStream;

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
      final routeMode = await VpnRouteModePrefs.getMode();
      final wantBundledRu =
          routeMode == VpnRouteMode.smart && kSmartRuSplitEnabled;
      final siteSuffixes = await SplitTunnelPrefs.enabledDomainSuffixes();
      final siteProxyCidrs = await SplitTunnelPrefs.enabledProxyIpCidrs();
      try {
        if (wantBundledRu || kAdsBlockEnabled) {
          localRules = await prepareLocalRuleSetPaths();
          ruRulesLoaded = kRuDomainRuleSetTags.every(localRules.containsKey);
        }
      } catch (e) {
        // Unit tests lack path_provider; connect still works without RU/ads split.
        // ignore: avoid_print
        print('[VPN] local rule-sets skipped: $e');
      }
      await VpnSessionMeta.saveConnectMeta(
        ruRulesLoaded: ruRulesLoaded,
        ruRuleTags: localRules.keys
            .where((t) => kRuDomainRuleSetTags.contains(t))
            .toList(),
        expectedEgressHost: config.expectedEgressHost,
      );
      final inputs = VpnSessionInputs.fromVpnConfig(
        config: config,
        service: serviceConfig,
        route: RoutePolicy(
          mode: routeMode,
          includeAdsBlock: kAdsBlockEnabled,
          includeGeoipRu: kGeoipRuEnabled,
          includeBundledRuRuleSets: wantBundledRu,
          proxyDomainSuffixes:
              routeMode == VpnRouteMode.sites ? siteSuffixes : const [],
          proxyIpCidrs:
              routeMode == VpnRouteMode.sites ? siteProxyCidrs : const [],
          localRulePaths: localRules,
        ),
      );
      final singBoxConfigJson = VpnConfigConstructor.build(inputs);
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

  /// Native session flag (`active=true`) — set on connect, cleared on intentional stop.
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

  /// Android Always-on "Block connections without VPN" preference.
  ///
  /// Reflects the system lockdown **setting**, not whether the tunnel is up.
  /// Prefer [queryLockdownState] when OFF vs query-failure must be distinct.
  Future<bool> isLockdownEnabled() async {
    return (await queryLockdownState()) == VpnLockdownState.enabled;
  }

  /// Observed Android lockdown preference: enabled / disabled / unavailable.
  ///
  /// Native returns a map `{lockdown, alwaysOn, …}` (or legacy bool). Lockdown
  /// true → [VpnLockdownState.enabled]; always-on without lockdown →
  /// [VpnLockdownState.alwaysOnOnly]; Secure unreadable → unavailable.
  Future<VpnLockdownState> queryLockdownState() async {
    try {
      final raw = await _methodChannel.invokeMethod<dynamic>('isLockdownEnabled');
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

  /// Opens system VPN settings (`Settings.ACTION_VPN_SETTINGS`). Returns false
  /// if the OEM has no matching activity or the launch fails.
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

  /// Live ↓/↑ from Android libbox (~1 Hz). Empty/zeros when disconnected or iOS.
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

  /// Live path RTT (ms) from libbox urlTest. Nulls filtered; invalid samples
  /// never leave the native monitor.
  Stream<int?> get pingStream {
    _pingStream ??= _pingEventChannel
        .receiveBroadcastStream()
        .map((event) {
          int? parsed;
          if (event is Map) {
            final ms = event['delayMs'];
            if (ms is num) {
              final v = ms.toInt();
              if (v >= 30 && v <= 5000) parsed = v;
            }
          } else if (event is num) {
            final v = event.toInt();
            if (v >= 30 && v <= 5000) parsed = v;
          }
          return parsed;
        })
        .handleError((_) => null);
    return _pingStream!;
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
/// Observed Android "Block connections without VPN" (Always-on lockdown).
///
/// [unavailable] means the platform query failed — never treat as [disabled].
enum VpnLockdownState {
  /// "Block connections without VPN" is on.
  enabled,

  /// Always-on VPN for Teremok without the block-without-VPN toggle.
  alwaysOnOnly,

  disabled,
  unavailable,
}

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

/// Live traffic rates from Android libbox (bytes per second).
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

  /// Compact tile label (matches shade units: B/s · KiB/s · MiB/s).
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