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
}
