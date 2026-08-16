import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/core/diagnostics/diagnostics_service.dart';
import 'package:teremok_connect/core/diagnostics/egress_verify.dart';

void main() {
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
}
