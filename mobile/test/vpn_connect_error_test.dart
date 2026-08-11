import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/features/vpn/domain/vpn_connect_error.dart';

void main() {
  group('parseSocksProbeFailure', () {
    test('parses native failStart message', () {
      final parsed = parseSocksProbeFailure(
        'eu-primary@204.11.2.216: SOCKS HTTPS probe failed',
      );
      expect(parsed?.nodeId, 'eu-primary');
      expect(parsed?.host, '204.11.2.216');
    });

    test('returns null for unrelated errors', () {
      expect(parseSocksProbeFailure('Xray start failed'), isNull);
    });
  });

  group('vpnErrorFromNativeDetail', () {
    test('maps probe fail to server_probe_failed code', () {
      final err = vpnErrorFromNativeDetail(
        'eu-primary@204.11.2.216: SOCKS HTTPS probe failed',
      );
      expect(err.code, kVpnProbeFailedErrorCode);
      expect(err.message, 'eu-primary');
    });

    test('falls back when detail empty', () {
      final err = vpnErrorFromNativeDetail(
        null,
        fallbackMessage: 'Failed to start VPN service',
      );
      expect(err.code, isNull);
      expect(err.message, 'Failed to start VPN service');
    });
  });
}
