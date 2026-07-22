import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/core/diagnostics/egress_verify.dart';

void main() {
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
