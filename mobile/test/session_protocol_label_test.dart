import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/features/vpn/data/vpn_node.dart';
import 'package:teremok_connect/features/vpn/data/vpn_service_config.dart';

void main() {
  test('Hy2 session is HYSTERIA2 not VLESS', () {
    expect(
      sessionProtocolLabel(
        config: null,
        selectedNodeProtocol: kVpnNodeProtocolHysteria2,
      ),
      'HYSTERIA2',
    );
  });

  test('TrustTunnel session is TRUSTTUNNEL', () {
    expect(
      sessionProtocolLabel(
        config: null,
        selectedNodeProtocol: kVpnNodeProtocolTrusttunnel,
      ),
      'TRUSTTUNNEL',
    );
  });
}
