import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/core/diagnostics/tunnel_log_redact.dart';

void main() {
  test('export masks node addresses and keeps the document host', () {
    const raw = 'vpn.phase host=203.0.113.8 '
        'doc.fetch host=api.teremokconnect.online '
        'core.vless dns=system socks=127.0.0.1:10809';
    final masked = redactTunnelLog(raw);
    expect(masked.contains('203.0.113.8'), isFalse);
    expect(masked.contains('127.0.0.1'), isFalse);
    expect(masked, contains('203.0.***.***'));
    expect(masked, contains('127.0.***.***'));
    expect(masked, contains('api.teremokconnect.online'));
    expect(masked, contains('vpn.phase'));
    expect(masked, contains('core.vless'));
  });

  test('export masks a share secret and keeps the host', () {
    const raw = 'dial hysteria2://secret+pass@cdn.example:443 '
        'vless://11111111-2222-3333-4444-555555555555@edge.example:443';
    final masked = redactTunnelLog(raw);
    expect(masked.contains('secret+pass'), isFalse);
    expect(masked.contains('11111111-2222-3333-4444-555555555555'), isFalse);
    expect(masked, contains('hysteria2://***@cdn.example:443'));
    expect(masked, contains('vless://***@edge.example:443'));
  });
}
