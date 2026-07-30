import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../config.dart';
import 'app_log_buffer.dart';
import 'egress_verify.dart';
import '../../features/auth/application/auth_state.dart';
import '../../features/home/application/vpn_status.dart';
import '../../features/vpn/data/vpn_config.dart';
import '../../features/vpn/data/vpn_controller.dart';
import '../../features/vpn/data/vpn_session_meta.dart';

/// Collects a beta diagnostic bundle and sends it to the owner via backend.
class DiagnosticsService {
  DiagnosticsService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  static String? lastFlutterError;

  Future<String> buildReport({
    required AuthState authState,
    required VpnStatus vpnUi,
    VpnConfig? cachedConfig,
  }) async {
    final generatedUtc = DateTime.now().toUtc().toIso8601String();
    final packageInfo = await PackageInfo.fromPlatform();
    final appLabel = 'Теремок VPN ${packageInfo.version}+${packageInfo.buildNumber}';

    final nativeStatus = await VpnController.instance.getStatus();
    final nativeError = await VpnController.instance.getLastError();
    final lockdown = await VpnController.instance.isLockdownEnabled();
    final stderrTail = await VpnController.instance.getSingBoxStderrTail();
    final underlying = await VpnController.instance.getUnderlyingNetworkInterface();

    final sessionMeta = await VpnSessionMeta.load();
    final config = cachedConfig ?? VpnConfigCache.instance.current;
    final expectedHost =
        sessionMeta.expectedEgressHost ?? config?.expectedEgressHost;

    final egress = await verifyEgress(expectedHost: expectedHost);

    final authLine = authState is AuthStateAuthenticated
        ? 'authenticated (tokens present, phone redacted)'
        : 'not_authenticated';

    final vpnUiLine = _vpnUiLabel(vpnUi);
    final lastVpnError = vpnUi is VpnError ? vpnUi.message : '(none)';

    final buffer = StringBuffer()
      ..writeln('generated_utc: $generatedUtc')
      ..writeln('app: $appLabel')
      ..writeln('package: ${packageInfo.packageName}')
      ..writeln('api_base: ${AppConfig.baseUrl}')
      ..writeln('app_env: ${const String.fromEnvironment('APP_ENV', defaultValue: 'prod')}')
      ..writeln('platform: ${_platformLabel()}')
      ..writeln('auth: $authLine')
      ..writeln('vpn_ui: $vpnUiLine')
      ..writeln('vpn_native: ${nativeStatus.name}')
      ..writeln('vpn_native_last_error: ${nativeError ?? '(none)'}')
      ..writeln('vpn_lockdown: $lockdown')
      ..writeln('external_ip: ${egress.externalIpLabel}')
      ..writeln('expected_egress_host: ${expectedHost ?? '(unknown)'}')
      ..writeln('egress_ok: ${egress.egressOkLabel}')
      ..writeln('ru_rules_loaded: ${sessionMeta.ruRulesLoaded}')
      ..writeln(
        'ru_rules_paths: ${sessionMeta.ruRuleTags.isEmpty ? '(none)' : sessionMeta.ruRuleTags.join(', ')}',
      )
      ..writeln('underlying_network: ${underlying ?? '(unsupported)'}')
      ..writeln('singbox_stderr_tail:')
      ..writeln(stderrTail ?? '(unsupported)')
      ..writeln('last_vpn_error: $lastVpnError')
      ..writeln('last_flutter_error: ${lastFlutterError ?? '(none)'}')
      ..writeln('--- recent_log ---')
      ..writeln(AppLogBuffer.instance.formatRecentLog());

    return buffer.toString().trim();
  }

  Future<void> submit({
    required String accessToken,
    required String report,
  }) async {
    await _dio.post<Map<String, dynamic>>(
      '${AppConfig.baseUrl}/support/diagnostics',
      data: {'report': report},
      options: Options(
        headers: {'Authorization': 'Bearer $accessToken'},
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 30),
      ),
    );
  }

  String _vpnUiLabel(VpnStatus status) => switch (status) {
        VpnDisconnected() => 'disconnected',
        VpnConnecting() => 'connecting',
        VpnConnected(:final serverName, :final protocol) =>
          'connected server=$serverName protocol=$protocol',
        VpnError(:final message) => 'error: $message',
      };

  String _platformLabel() {
    if (Platform.isAndroid) {
      return 'android ${Platform.operatingSystemVersion}';
    }
    if (Platform.isIOS) {
      return 'ios ${Platform.operatingSystemVersion}';
    }
    if (Platform.isWindows) {
      return 'windows ${Platform.operatingSystemVersion}';
    }
    return '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
  }
}

/// Captures Flutter framework errors for diagnostic reports.
void installFlutterErrorHandler({void Function()? onCrashObserved}) {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    DiagnosticsService.lastFlutterError =
        details.exceptionAsString().split('\n').first;
    AppLogBuffer.instance.warn(
      'flutter: ${DiagnosticsService.lastFlutterError}',
    );
    try {
      onCrashObserved?.call();
    } catch (_) {
      // Never let analytics hooks break error handling.
    }
    previous?.call(details);
  };
}
