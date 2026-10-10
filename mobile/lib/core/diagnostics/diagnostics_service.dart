import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'app_log_buffer.dart';
import 'tunnel_log_redact.dart';
import 'egress_verify.dart';
import '../../features/home/application/vpn_status.dart';
import '../../features/vpn/data/vpn_controller.dart';

/// Collects a local diagnostic bundle for the user to paste into support.
class DiagnosticsService {
  DiagnosticsService();

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

  /// The dialed host, for the Pixel E2E check (IP↔IP against icanhazip, not SNI).
  static String formatCatalogHost(String? host) {
    final trimmed = host?.trim();
    if (trimmed == null || trimmed.isEmpty) return '(none)';
    return trimmed;
  }

  Future<String> buildReport({
    required VpnStatus vpnUi,
    String? autoWinnerId,
    String? autoWinnerLabel,
    String? lastProve,
    String? catalogHost,
  }) async {
    final generatedUtc = DateTime.now().toUtc().toIso8601String();
    final packageInfo = await PackageInfo.fromPlatform();
    final appLabel =
        'Прокси Дом ${packageInfo.version}+${packageInfo.buildNumber}';

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
    final nativeLogTail =
        await _probe(VpnController.instance.getNativeLogTail());
    final tunnelHealth = await _probeHealth();
    final underlying = await _probe(
      VpnController.instance.getUnderlyingNetworkInterface(),
    );

    final egress = await _probeEgress(null);

    final vpnUiLine = _vpnUiLabel(vpnUi);
    final lastVpnError = vpnUi is VpnError ? vpnUi.message : '(none)';

    final buffer = StringBuffer()
      ..writeln('generated_utc: $generatedUtc')
      ..writeln('app: $appLabel')
      ..writeln('package: ${packageInfo.packageName}')
      ..writeln(
          'app_env: ${const String.fromEnvironment('APP_ENV', defaultValue: 'prod')}')
      ..writeln('platform: ${_platformLabel()}')
      ..writeln('vpn_ui: $vpnUiLine')
      ..writeln('vpn_native: ${nativeStatus.name}')
      ..writeln('vpn_native_last_error: ${nativeError ?? '(none)'}')
      ..writeln('vpn_lockdown: $lockdown')
      ..writeln('external_ip: ${egress.externalIpLabel}')
      ..writeln('underlying_network: ${underlying ?? '(unsupported)'}')
      ..writeln('last_prove: ${lastProve ?? '(none)'}')
      ..writeln('vpn_stderr_tail:')
      ..writeln(redactTunnelLog(stderrTail ?? '(unsupported)'))
      ..writeln('ios_native_tail:')
      // Same mask as the stderr tail above. The iOS ring holds `pin=<node ip>`
      // and unredacted engine error text, and this is the line that leaves the
      // device when the user taps «Отправить отчёт».
      ..writeln(redactTunnelLog(nativeLogTail ?? '(unsupported)'))
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
  ///
  /// Redacted first. `debugPrint` lands in the device system log, which on
  /// older Android builds any app with READ_LOGS could read — a report is
  /// meant to leave the phone, not to be broadcast from it.
  static void dumpReportToLogcat(String report) {
    final safe = redactTunnelLog(report);
    debugPrint('=== DIAG-REPORT BEGIN ===', wrapWidth: logcatChunkChars);
    for (var i = 0; i < safe.length; i += logcatChunkChars) {
      final end = i + logcatChunkChars > safe.length
          ? safe.length
          : i + logcatChunkChars;
      debugPrint(safe.substring(i, end), wrapWidth: logcatChunkChars);
    }
    debugPrint('=== DIAG-REPORT END ===', wrapWidth: logcatChunkChars);
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

/// How many lines of a Flutter error report are copied into the log ring.
///
/// A layout overflow names the widget it happened in on the lines *after* the
/// headline — "The relevant error-causing widget was:" plus the creator chain —
/// and that is the only part that makes a field report actionable. Only the
/// headline used to be kept, so an exported log could say that a RenderFlex
/// overflowed by 52 pixels without ever saying where.
///
/// Bounded because the ring holds [AppLogBuffer.maxLines] lines and a layout
/// error that repeats on every frame must not flush the session out of it.
const int kFlutterErrorLogLines = 30;

/// Captures Flutter framework errors for diagnostic reports.
void installFlutterErrorHandler({void Function()? onCrashObserved}) {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    DiagnosticsService.lastFlutterError =
        details.exceptionAsString().split('\n').first;
    // exceptionAsString() is the summary alone. FlutterErrorDetails.toString()
    // is the whole report the console shows, because its diagnostics node pulls
    // in the informationCollector that carries the widget chain and the stack.
    var kept = 0;
    for (final line in details.toString().split('\n')) {
      AppLogBuffer.instance.debug('flutter: $line');
      if (++kept >= kFlutterErrorLogLines) break;
    }
    try {
      onCrashObserved?.call();
    } catch (_) {
      // Never let analytics hooks break error handling.
    }
    previous?.call(details);
  };
}
