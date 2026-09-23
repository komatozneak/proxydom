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
