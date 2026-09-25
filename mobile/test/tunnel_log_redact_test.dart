import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/core/diagnostics/tunnel_log_redact.dart';

void main() {
  test('export masks node addresses and keeps the document host', () {
    const raw = 'vpn.phase host=203.0.113.8 '
        'doc.fetch host=api.teremokconnect.online '
        'core.xray dns=system socks=127.0.0.1:10809';
    final masked = redactTunnelLog(raw);
    expect(masked.contains('203.0.113.8'), isFalse);
    expect(masked.contains('127.0.0.1'), isFalse);
    expect(masked, contains('203.0.***.***'));
    expect(masked, contains('127.0.***.***'));
    expect(masked, contains('api.teremokconnect.online'));
    expect(masked, contains('vpn.phase'));
    expect(masked, contains('core.xray'));
  });
}
