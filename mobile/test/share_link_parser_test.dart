import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/features/vpn/data/share_link_parser.dart';

void main() {
  test('parses vless, trojan, and hysteria2 in one list', () {
    const body = '''
vless://11111111-1111-1111-1111-111111111111@203.0.113.10:443?security=tls&sni=a.example#Alpha
trojan://secret@203.0.113.11:8443?sni=b.example#Bravo
hysteria2://user:pass@203.0.113.12:443/?sni=c.example#Charlie
''';
    final links = parseShareSubscription(body);
    expect(links.map((e) => e.scheme).toList(), [
      'vless',
      'trojan',
      'hysteria2',
    ]);
    expect(links[0].endpoint, '203.0.113.10:443');
    expect(links[0].name, 'Alpha');
    expect(links[1].isHysteria2, isFalse);
    expect(links[2].hy2?.profile.sni, 'c.example');
  });

  test('parses vmess base64 json and legacy ss blob', () {
    final vmess = base64Encode(
      utf8.encode(
        '{"add":"203.0.113.20","port":"443","ps":"Mike","id":"abc"}',
      ),
    );
    final ss = base64Encode(utf8.encode('aes-256-gcm:secret@203.0.113.21:8388'));
    final links = parseShareSubscription('vmess://$vmess\nss://$ss#Shadow\n');
    expect(links[0].scheme, 'vmess');
    expect(links[0].name, 'Mike');
    expect(links[0].endpoint, '203.0.113.20:443');
    expect(links[1].scheme, 'ss');
    expect(links[1].endpoint, '203.0.113.21:8388');
    expect(links[1].name, 'Shadow');
  });

  test('base64 subscription body unwraps to uri lines', () {
    const plain = 'vless://u@203.0.113.30:443#Wrapped\n';
    final blob = base64Encode(utf8.encode(plain));
    final links = parseShareSubscription(blob);
    expect(links, hasLength(1));
    expect(links.single.name, 'Wrapped');
  });
}
