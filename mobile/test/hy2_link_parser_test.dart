import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/features/vpn/data/hy2_link_parser.dart';

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
        'hysteria2://user:pass@45.91.248.91:443/?sni=hy2-us.company-net.ru'
        '#%D0%A1%D0%A8%D0%90%20%C2%B7%20%D0%A1%D0%B5%D1%80%D0%B2%D0%B8%D1%81%D1%8B';
    final parsed = parseHy2Link(uri);
    expect(parsed.name, 'США');
    expect(parsed.profile.server, '45.91.248.91:443');
    expect(parsed.profile.sni, 'hy2-us.company-net.ru');
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
    const uri = 'hysteria2://standHy2pass@95.182.81.27:20002'
        '?sni=stand.company-net.test&insecure=1&obfs=salamander'
        '&obfs-password=standObfsPass#hy2-obfs';
    final parsed = parseHy2Link(uri);
    expect(parsed.profile.insecure, isTrue);
    expect(parsed.profile.obfs, 'salamander');
    expect(parsed.profile.obfsPassword, 'standObfsPass');
  });

  test('numeric fm timers and brutal congestion are kept, bandwidth is not',
      () {
    final fm = jsonEncode({
      'quicParams': {
        'brutalUp': '2000 mbps',
        'brutalDown': '2000 mbps',
        'congestion': 'brutal',
        'maxIdleTimeout': 20,
        'keepAlivePeriod': 10,
      },
    });
    final uri =
        'hy2://user:pass@203.0.113.10:443/?sni=edge.example&fm=${Uri.encodeQueryComponent(fm)}#DE';
    final parsed = parseHy2Link(uri);
    expect(parsed.profile.maxIdleTimeout, '20');
    expect(parsed.profile.keepAlivePeriod, '10');
    expect(parsed.profile.congestion, 'brutal');
    expect(parsed.profile.bandwidthUp, isNull);
    expect(parsed.profile.bandwidthDown, isNull);
    expect(
      parsed.profile.fmDeclared,
      'quicParams.brutalUp,quicParams.brutalDown,quicParams.congestion,'
      'quicParams.maxIdleTimeout,quicParams.keepAlivePeriod',
    );
    expect(parsed.profile.fmDeclared, isNot(contains('2000')));
    expect(parsed.profile.fmDeclared, isNot(contains('mbps')));
  });

  test('string fm timers parse the same way as numbers', () {
    final fm = jsonEncode({
      'quicParams': {
        'maxIdleTimeout': '20',
        'keepAlivePeriod': '10',
      },
    });
    final uri =
        'hy2://user:pass@203.0.113.10:443/?fm=${Uri.encodeQueryComponent(fm)}';
    final parsed = parseHy2Link(uri);
    expect(parsed.profile.maxIdleTimeout, '20');
    expect(parsed.profile.keepAlivePeriod, '10');
  });

  test('maxIdleTimeout of 1 is forwarded for the engine to clamp', () {
    final fm = jsonEncode({
      'quicParams': {'maxIdleTimeout': 1},
    });
    final uri =
        'hy2://user:pass@203.0.113.10:443/?fm=${Uri.encodeQueryComponent(fm)}';
    final parsed = parseHy2Link(uri);
    expect(parsed.profile.maxIdleTimeout, '1');
    expect(parsed.profile.keepAlivePeriod, isEmpty);
  });

  test('keepAlivePeriode22 typo is the keepalive', () {
    final fm = jsonEncode({
      'quicParams': {'keepAlivePeriode22': 10},
    });
    final uri =
        'hy2://user:pass@203.0.113.10:443/?fm=${Uri.encodeQueryComponent(fm)}';
    final parsed = parseHy2Link(uri);
    expect(parsed.profile.keepAlivePeriod, '10');
    expect(parsed.profile.fmDeclared, 'quicParams.keepAlivePeriode22');
  });

  test('flat snake and kebab timer keys are read', () {
    const uri = 'hy2://user:pass@203.0.113.10:443/'
        '?max-idle-timeout=15&keep_alive_period=5&Congestion=reno';
    final parsed = parseHy2Link(uri);
    expect(parsed.profile.maxIdleTimeout, '15');
    expect(parsed.profile.keepAlivePeriod, '5');
    expect(parsed.profile.congestion, 'reno');
    expect(parsed.profile.fmDeclared, contains('max-idle-timeout'));
    expect(parsed.profile.fmDeclared, contains('keep_alive_period'));
    expect(parsed.profile.fmDeclared, contains('Congestion'));
  });

  test('nested quicParams wins over a flat timer', () {
    final fm = jsonEncode({
      'quicParams': {'maxIdleTimeout': 20},
    });
    final uri = 'hy2://user:pass@203.0.113.10:443/'
        '?maxIdleTimeout=1&fm=${Uri.encodeQueryComponent(fm)}';
    final parsed = parseHy2Link(uri);
    expect(parsed.profile.maxIdleTimeout, '20');
  });

  test('a broken fm does not reject the link', () {
    const uri = 'hy2://user:pass@203.0.113.10:443/?sni=edge.example&fm=%7Bnot';
    final parsed = parseHy2Link(uri);
    expect(parsed.profile.sni, 'edge.example');
    expect(parsed.profile.maxIdleTimeout, isEmpty);
    expect(parsed.profile.congestion, isEmpty);
    expect(parsed.profile.fmDeclared, isEmpty);
  });

  test('a catalog link without fm leaves timers and congestion empty', () {
    const uri =
        'hysteria2://user:pass@203.0.113.12:443/?sni=hy2-us.company-net.ru';
    final parsed = parseHy2Link(uri);
    expect(parsed.profile.maxIdleTimeout, isEmpty);
    expect(parsed.profile.keepAlivePeriod, isEmpty);
    expect(parsed.profile.congestion, isEmpty);
    expect(parsed.profile.bbrProfile, isEmpty);
    expect(parsed.profile.fmDeclared, isEmpty);
    expect(parsed.profile.bandwidthUp, isNull);
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
