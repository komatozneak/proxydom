import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../api_client.dart';
import '../config.dart';
import '../ios_store_gates.dart';
import 'app_log_buffer.dart';
import 'egress_verify.dart';
import '../../features/auth/application/auth_state.dart';
import '../../features/home/application/vpn_status.dart';
import '../../features/vpn/data/vpn_config.dart';
import '../../features/vpn/data/vpn_controller.dart';
import '../../features/vpn/data/vpn_session_meta.dart';

/// Collects a local diagnostic bundle for the user to paste into support.
class DiagnosticsService {
  DiagnosticsService({Dio? dio}) : _dio = dio ?? ApiClient.instance;

  final Dio _dio;

  static String? lastFlutterError;

  /// Backend [DiagnosticsReportIn] max_length is 120_000.
  static const int telegramMaxChars = 120000;

  /// Leave headroom for JSON wrapping when POSTing to Telegram.
  static const int postMaxChars = 110000;

  static const int logcatChunkChars = 800;

  /// Native health/logs must not hang Settings (iOS sendProviderMessage).
  @visibleForTesting
  static Duration nativeProbeTimeout = const Duration(seconds: 3);

  @visibleForTesting
  static Duration egressProbeTimeout = const Duration(seconds: 5);

  /// Catalog `VpnNode.host` for Pixel E2E (IP↔IP vs icanhazip, not SNI).
  static String formatCatalogHost(String? host) {
    final trimmed = host?.trim();
    if (trimmed == null || trimmed.isEmpty) return '(none)';
    return trimmed;
  }

  Future<String> buildReport({
    required AuthState authState,
    required VpnStatus vpnUi,
    VpnConfig? cachedConfig,
    String? autoWinnerId,
    String? autoWinnerLabel,
    String? lastProve,
    String? catalogHost,
  }) async {
    final generatedUtc = DateTime.now().toUtc().toIso8601String();
    final packageInfo = await PackageInfo.fromPlatform();
    final appLabel = 'Теремок VPN ${packageInfo.version}+${packageInfo.buildNumber}';

    final nativeStatus = await _probe(
          VpnController.instance.getStatus(),
        ) ??
        VpnNativeStatus.unknown;
    final nativeError = await _probe(VpnController.instance.getLastError());
    final lockdown =
        await _probe(VpnController.instance.isLockdownEnabled()) ?? false;
    final stderrTail = await _probe(
      VpnController.instance.getVpnCoreStderrTail(maxLines: 400),
    );
    final nativeLogTail = await _probe(VpnController.instance.getNativeLogTail());
    final tunnelHealth = await _probeHealth();
    final underlying = await _probe(
      VpnController.instance.getUnderlyingNetworkInterface(),
    );

    final sessionMeta = await VpnSessionMeta.load();
    final config = cachedConfig ?? VpnConfigCache.instance.current;
    final expectedHost = freeKeyClient
        ? null
        : sessionMeta.expectedEgressHost ?? config?.expectedEgressHost;

    final egress = await _probeEgress(expectedHost);

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
      ..writeln('external_ip: ${egress.externalIpLabel}');
    if (!freeKeyClient) {
      buffer
        ..writeln('catalog_host: ${formatCatalogHost(catalogHost)}')
        ..writeln('expected_egress_host: ${expectedHost ?? '(unknown)'}')
        ..writeln('egress_ok: ${egress.egressOkLabel}')
        ..writeln(
          'egress_check: ${egressCheckLabel(externalIp: egress.externalIp, catalogHost: catalogHost)}',
        )
        ..writeln('ru_rules_loaded: ${sessionMeta.ruRulesLoaded}')
        ..writeln(
          'ru_rules_paths: ${sessionMeta.ruRuleTags.isEmpty ? '(none)' : sessionMeta.ruRuleTags.join(', ')}',
        );
    }
    buffer.writeln('underlying_network: ${underlying ?? '(unsupported)'}');
    if (!freeKeyClient) {
      buffer
        ..writeln('auto_winner_id: ${autoWinnerId ?? '(none)'}')
        ..writeln('auto_winner_label: ${autoWinnerLabel ?? '(none)'}');
    }
    buffer
      ..writeln('last_prove: ${lastProve ?? '(none)'}')
      ..writeln('vpn_stderr_tail:')
      ..writeln(stderrTail ?? '(unsupported)')
      ..writeln('ios_native_tail:')
      ..writeln(nativeLogTail ?? '(unsupported)')
      ..writeln('ios_tunnel_health:')
      ..writeln(tunnelHealth)
      ..writeln('last_vpn_error: $lastVpnError')
      ..writeln('last_flutter_error: ${lastFlutterError ?? '(none)'}')
      ..writeln('--- recent_log ---')
      ..writeln(AppLogBuffer.instance.formatRecentLog());

    return buffer.toString().trim();
  }

  /// Short id for local persist + snackbar (no secrets).
  static String newReportId() {
    final ms = DateTime.now().toUtc().millisecondsSinceEpoch;
    final suffix = Random().nextInt(0xFFFF).toRadixString(16).padLeft(4, '0');
    return 'r$ms$suffix';
  }

  /// Write the bundle on-device. Success of «Send report» is this file, not Telegram.
  static Future<({String reportId, String body, File? file})> persistLocal(
    String report, {
    Directory? directory,
  }) async {
    final reportId = newReportId();
    final body = 'report_id: $reportId\n$report';
    dumpReportToLogcat(body);
    File? file;
    try {
      final dir = directory ?? await getApplicationSupportDirectory();
      file = File('${dir.path}/diag_$reportId.txt');
      await file.writeAsString(body);
    } catch (_) {
      file = null;
    }
    return (reportId: reportId, body: body, file: file);
  }

  /// Last [postMaxChars] so Telegram accepts the POST; logcat still gets the full bundle.
  static String clipForPost(String report) {
    if (report.length <= postMaxChars) return report;
    return report.substring(report.length - postMaxChars);
  }

  /// Dump the full bundle to `flutter run` / logcat (Cursor reads the terminal).
  static void dumpReportToLogcat(String report) {
    debugPrint('=== DIAG-REPORT BEGIN ===', wrapWidth: logcatChunkChars);
    for (var i = 0; i < report.length; i += logcatChunkChars) {
      final end = i + logcatChunkChars > report.length
          ? report.length
          : i + logcatChunkChars;
      debugPrint(report.substring(i, end), wrapWidth: logcatChunkChars);
    }
    debugPrint('=== DIAG-REPORT END ===', wrapWidth: logcatChunkChars);
  }

  Future<void> submit({
    required String report,
    bool dumpToLogcat = true,
  }) async {
    if (dumpToLogcat) dumpReportToLogcat(report);
    final payload = clipForPost(report);
    final resp = await _dio.post<Map<String, dynamic>>(
      '/support/diagnostics',
      data: {'report': payload},
      options: Options(
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 30),
      ),
    );
    final code = resp.statusCode ?? 0;
    if (code < 200 || code >= 300) {
      throw DioException(
        requestOptions: resp.requestOptions,
        response: resp,
        type: DioExceptionType.badResponse,
        message: 'diagnostics failed: $code',
      );
    }
  }

  Future<T?> _probe<T>(Future<T?> future) async {
    try {
      return await future.timeout(nativeProbeTimeout);
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<String> _probeHealth() async {
    try {
      final health = await VpnController.instance
          .getTunnelHealth()
          .timeout(nativeProbeTimeout);
      if (health == null || health.isEmpty) return '(none)';
      return health;
    } on TimeoutException {
      return '(timeout)';
    } catch (_) {
      return '(none)';
    }
  }

  Future<EgressVerifyResult> _probeEgress(String? expectedHost) async {
    try {
      return await verifyEgress(expectedHost: expectedHost)
          .timeout(egressProbeTimeout);
    } on TimeoutException {
      return EgressVerifyResult(
        externalIp: null,
        expectedHost: expectedHost,
        egressOk: null,
      );
    } catch (_) {
      return EgressVerifyResult(
        externalIp: null,
        expectedHost: expectedHost,
        egressOk: null,
      );
    }
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
    AppLogBuffer.instance.debug(
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
