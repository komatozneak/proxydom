import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/features/vpn/data/hy2_link_parser.dart';

void main() {
  test('parseHy2Link keeps plus in the password', () {
    const uri =
        'hysteria2://hy2u:pass%2Bword@217.60.3.9:443/?sni=eu.example.com#Europe';
    final parsed = parseHy2Link(uri);
    expect(parsed.profile.auth, 'hy2u:pass+word');
    expect(parsed.profile.server, '217.60.3.9:443');
    expect(parsed.profile.sni, 'eu.example.com');
    expect(parsed.name, 'Europe');
  });

  test('percent-encoded remark becomes the server title', () {
    const uri =
        'hysteria2://user:pass@45.91.248.91:443/?sni=hy2-us.teremokconnect.online'
        '#%D0%A1%D0%A8%D0%90%20%C2%B7%20%D0%A1%D0%B5%D1%80%D0%B2%D0%B8%D1%81%D1%8B';
    final parsed = parseHy2Link(uri);
    expect(parsed.name, 'США');
    expect(parsed.profile.server, '45.91.248.91:443');
    expect(parsed.profile.sni, 'hy2-us.teremokconnect.online');
    expect(parsed.profile.auth, 'user:pass');
    expect(parsed.profile.nodeId, '45.91.248.91');
  });

  test('parseHy2Subscription reads several lines and skips comments', () {
    const body = '''
# comment
hysteria2://a:b@1.2.3.4:443/?sni=a.example.com#A
hy2://c:d@5.6.7.8:443/?sni=b.example.com#B
''';
    final links = parseHy2Subscription(body);
    expect(links, hasLength(2));
    expect(links.first.profile.server, '1.2.3.4:443');
    expect(links.last.name, 'B');
  });

  test('omitted sni uses the host as the TLS name', () {
    const uri = 'hysteria2://user:pass@203.0.113.12:443#Plain';
    final parsed = parseHy2Link(uri);
    expect(parsed.profile.sni, '203.0.113.12');
    expect(parsed.profile.server, '203.0.113.12:443');
    expect(parsed.name, 'Plain');
  });

  test('an explicit sni query still wins over the host', () {
    const uri = 'hy2://user:pass@203.0.113.12:443/?sni=edge.example#Named';
    final parsed = parseHy2Link(uri);
    expect(parsed.profile.sni, 'edge.example');
    expect(parsed.name, 'Named');
  });

  test('insecure and salamander are kept on the profile', () {
    const uri =
        'hysteria2://standHy2pass@95.182.81.27:20002'
        '?sni=stand.teremok.test&insecure=1&obfs=salamander'
        '&obfs-password=standObfsPass#hy2-obfs';
    final parsed = parseHy2Link(uri);
    expect(parsed.profile.insecure, isTrue);
    expect(parsed.profile.obfs, 'salamander');
    expect(parsed.profile.obfsPassword, 'standObfsPass');
  });

  test('https subscription url is not a hy2 scheme', () {
    expect(
      looksLikeSubscriptionUrl('https://api.example/sub/token'),
      isTrue,
    );
    expect(
      looksLikeSubscriptionUrl('hysteria2://a:b@1.2.3.4:443/?sni=a.example#A'),
      isFalse,
    );
  });
}
