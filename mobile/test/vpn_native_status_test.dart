import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/features/vpn/data/vpn_controller.dart';

void main() {
  group('parseVpnNativeStatus', () {
    test('maps probing to connecting', () {
      expect(parseVpnNativeStatus('probing'), VpnNativeStatus.connecting);
    });

    test('maps known legacy strings', () {
      expect(parseVpnNativeStatus('idle'), VpnNativeStatus.idle);
      expect(parseVpnNativeStatus('preparing'), VpnNativeStatus.preparing);
      expect(parseVpnNativeStatus('connecting'), VpnNativeStatus.connecting);
      expect(parseVpnNativeStatus('connected'), VpnNativeStatus.connected);
      expect(parseVpnNativeStatus('disconnecting'), VpnNativeStatus.disconnecting);
      expect(parseVpnNativeStatus('revoked'), VpnNativeStatus.revoked);
      expect(parseVpnNativeStatus('error'), VpnNativeStatus.error);
    });

    test('unknown and empty become unknown', () {
      expect(parseVpnNativeStatus(null), VpnNativeStatus.unknown);
      expect(parseVpnNativeStatus(''), VpnNativeStatus.unknown);
      expect(parseVpnNativeStatus('nope'), VpnNativeStatus.unknown);
    });
  });
}
