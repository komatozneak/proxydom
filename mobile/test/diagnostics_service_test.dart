import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teremok_connect/core/diagnostics/diagnostics_service.dart';
import 'package:teremok_connect/core/diagnostics/egress_verify.dart';
import 'package:teremok_connect/features/home/application/vpn_status.dart';
import 'package:teremok_connect/features/vpn/data/vpn_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const vpnChannel = MethodChannel('teremok/vpn');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(vpnChannel, null);
  });

  group('DiagnosticsService.clipForPost', () {
    test('keeps short reports intact', () {
      const report = 'short bundle';
      expect(DiagnosticsService.clipForPost(report), report);
    });

    test('keeps the tail when over the Telegram POST cap', () {
      final report = 'H' * 50 + 'T' * DiagnosticsService.postMaxChars;
      final clipped = DiagnosticsService.clipForPost(report);
      expect(clipped.length, DiagnosticsService.postMaxChars);
      expect(clipped.startsWith('T'), isTrue);
      expect(clipped.contains('H'), isFalse);
      expect(clipped.length, lessThan(DiagnosticsService.telegramMaxChars));
    });
  });

  group('DiagnosticsService.formatCatalogHost', () {
    test('keeps catalog IPv4 for IP↔IP compare', () {
      expect(
        DiagnosticsService.formatCatalogHost('217.60.3.9'),
        '217.60.3.9',
      );
      expect(
        DiagnosticsService.formatCatalogHost('45.91.248.91'),
        '45.91.248.91',
      );
    });

    test('uses (none) when catalog host is missing', () {
      expect(DiagnosticsService.formatCatalogHost(null), '(none)');
      expect(DiagnosticsService.formatCatalogHost('  '), '(none)');
    });
  });

  group('EgressVerifyResult', () {
    test('egressOkLabel reflects match state', () {
      const ok = EgressVerifyResult(
        externalIp: '204.11.2.216',
        expectedHost: '204.11.2.216',
        egressOk: true,
      );
      expect(ok.egressOkLabel, 'true');
      expect(ok.externalIpLabel, '204.11.2.216');

      const bad = EgressVerifyResult(
        externalIp: '1.2.3.4',
        expectedHost: '204.11.2.216',
        egressOk: false,
      );
      expect(bad.egressOkLabel, 'false');

      const unknown = EgressVerifyResult(
        externalIp: null,
        expectedHost: '204.11.2.216',
        egressOk: null,
      );
      expect(unknown.egressOkLabel, 'unknown');
      expect(unknown.externalIpLabel, '(unavailable)');
    });
  });

  group('egressCheckLabel', () {
    test('matches catalog IPv4', () {
      expect(
        egressCheckLabel(
          externalIp: '217.60.3.9',
          catalogHost: '217.60.3.9',
        ),
        'match',
      );
    });

    test('SNI hostname is inconclusive not a dead tunnel', () {
      expect(
        egressCheckLabel(
          externalIp: '217.60.3.9',
          catalogHost: 'hy2-eu.teremokconnect.online',
        ),
        'inconclusive',
      );
    });

    test('unequal IPv4 is NAT not a dead tunnel', () {
      expect(
        egressCheckLabel(
          externalIp: '212.164.38.47',
          catalogHost: '217.60.3.9',
        ),
        'nat',
      );
    });
  });

  group('DiagnosticsService.persistLocal', () {
    test('writes report_id prefix to a file', () async {
      final dir = await Directory.systemTemp.createTemp('diag_');
      addTearDown(() => dir.delete(recursive: true));
      final saved = await DiagnosticsService.persistLocal(
        'vpn_ui: disconnected',
        directory: dir,
      );
      expect(saved.reportId, startsWith('r'));
      expect(saved.body, contains('report_id: ${saved.reportId}'));
      expect(saved.body, contains('vpn_ui: disconnected'));
      expect(saved.file, isNotNull);
      expect(saved.file!.existsSync(), isTrue);
      expect(saved.file!.readAsStringSync(), saved.body);
    });
  });

  group('ios_native_tail', () {
    test('VpnController.getNativeLogTail returns channel string', () async {
      messenger.setMockMethodCallHandler(vpnChannel, (call) async {
        if (call.method == 'getNativeLogTail') {
          return 'PacketTunnel.stopTunnel reason=1 gen=2';
        }
        return null;
      });
      final tail = await VpnController.instance.getNativeLogTail();
      expect(tail, contains('stopTunnel reason=1'));
    });

    test('buildReport includes ios_native_tail block', () async {
      SharedPreferences.setMockInitialValues({});
      const packageChannel =
          MethodChannel('dev.fluttercommunity.plus/package_info');
      messenger.setMockMethodCallHandler(packageChannel, (call) async {
        return <String, dynamic>{
          'appName': 'Teremok',
          'packageName': 'online.teremokconnect.app',
          'version': '0.1.15',
          'buildNumber': '2034',
        };
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(packageChannel, null);
      });

      messenger.setMockMethodCallHandler(vpnChannel, (call) async {
        switch (call.method) {
          case 'getStatus':
            return 'idle';
          case 'getLastError':
            return null;
          case 'isLockdownEnabled':
            return false;
          case 'getSingBoxStderrTail':
            return null;
          case 'getNativeLogTail':
            return 'NEVPNStatusDidChange mapped=idle';
          case 'getUnderlyingNetworkInterface':
            return null;
          default:
            return null;
        }
      });

      final report = await DiagnosticsService().buildReport(
        vpnUi: const VpnDisconnected(),
      );
      expect(report, contains('ios_native_tail:'));
      expect(report, contains('NEVPNStatusDidChange mapped=idle'));
    });

    test('buildReport returns when getTunnelHealth never completes', () async {
      SharedPreferences.setMockInitialValues({});
      DiagnosticsService.nativeProbeTimeout = const Duration(milliseconds: 40);
      DiagnosticsService.egressProbeTimeout = const Duration(milliseconds: 40);
      addTearDown(() {
        DiagnosticsService.nativeProbeTimeout = const Duration(seconds: 3);
        DiagnosticsService.egressProbeTimeout = const Duration(seconds: 5);
      });
      const packageChannel =
          MethodChannel('dev.fluttercommunity.plus/package_info');
      messenger.setMockMethodCallHandler(packageChannel, (call) async {
        return <String, dynamic>{
          'appName': 'Teremok',
          'packageName': 'online.teremokconnect.app',
          'version': '0.1.15',
          'buildNumber': '2034',
        };
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(packageChannel, null);
      });

      messenger.setMockMethodCallHandler(vpnChannel, (call) async {
        if (call.method == 'getTunnelHealth') {
          await Completer<void>().future;
        }
        switch (call.method) {
          case 'getStatus':
            return 'idle';
          case 'isLockdownEnabled':
            return false;
          default:
            return null;
        }
      });

      final report = await DiagnosticsService().buildReport(
        vpnUi: const VpnDisconnected(),
      );
      expect(report, contains('ios_tunnel_health:'));
      expect(report, contains('(timeout)'));
    });
  });
}
