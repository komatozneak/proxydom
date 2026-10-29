import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/features/vpn/data/subscription_traffic.dart';

void main() {
  const gib = 1024 * 1024 * 1024;
  const gb = 1000 * 1000 * 1000;
  const tb = 1000 * 1000 * 1000 * 1000;

  test('a manifest uses decimal total minus upload and download', () {
    final traffic = parseSubscriptionTraffic(
      'upload=${2 * gb}; download=0; total=${50 * gb}; expire=1700000000',
    );
    expect(traffic, isNotNull);
    expect(traffic!.remainingBytes, 48 * gb);
    expect(
      formatSubscriptionTraffic(traffic, russian: true, decimal: true),
      '48 ГБ',
    );
    expect(
      formatSubscriptionTraffic(traffic, russian: false, decimal: true),
      '48 GB',
    );
  });

  test('legacy headers stay binary', () {
    final traffic = parseSubscriptionTraffic(
      'upload=${2 * gib}; download=0; total=${50 * gib}',
    );
    expect(formatSubscriptionTraffic(traffic, russian: true), '48 ГБ');
    expect(
      formatTrafficAmount(100 * gib, russian: true),
      '100 ГБ',
    );
  });

  test('under 10 GB keeps one decimal', () {
    final remaining = (1.4 * gb).round();
    final traffic = parseSubscriptionTraffic(
      'upload=0; download=${2 * gb - remaining}; total=${2 * gb}',
    );
    expect(
      formatSubscriptionTraffic(traffic, russian: true, decimal: true),
      '1,4 ГБ',
    );
    expect(
      formatSubscriptionTraffic(traffic, russian: false, decimal: true),
      '1.4 GB',
    );
  });

  test('1 TB stays a terabyte instead of 931 GB', () {
    final traffic = parseSubscriptionTraffic(
      'upload=${27 * gb}; download=0; total=$tb',
    );
    expect(
      formatSubscriptionTraffic(traffic, russian: true, decimal: true),
      '973 ГБ',
    );
    expect(
      formatTrafficAmount(tb, russian: true, decimal: true),
      '1 ТБ',
    );
    expect(
      formatTrafficAmount(tb, russian: false, decimal: true),
      '1 TB',
    );
    expect(
      formatTrafficAmount((1.5 * tb).round(), russian: true, decimal: true),
      '1,5 ТБ',
    );
  });

  test('under 1 GB is shown in megabytes', () {
    const used = 50 * 1000 * 1000;
    final traffic = parseSubscriptionTraffic(
      'upload=$used; download=0; total=${80 * 1000 * 1000}',
    );
    expect(
      formatSubscriptionTraffic(traffic, russian: true, decimal: true),
      '30 МБ',
    );
    expect(
      formatSubscriptionTraffic(traffic, russian: false, decimal: true),
      '30 MB',
    );
  });

  test('used above total floors at zero', () {
    final traffic = parseSubscriptionTraffic(
      'upload=${3 * gib}; download=${gib}; total=${2 * gib}',
    );
    expect(traffic!.remainingBytes, 0);
    expect(formatSubscriptionTraffic(traffic, russian: true), '0 МБ');
  });

  test('zero total is unlimited', () {
    final traffic = parseSubscriptionTraffic(
      'upload=10; download=20; total=0',
    );
    expect(traffic!.unlimited, isTrue);
    expect(formatSubscriptionTraffic(traffic, russian: true), '∞');
  });

  test('a broken header and a missing header stay empty', () {
    expect(parseSubscriptionTraffic('not a header'), isNull);
    expect(parseSubscriptionTraffic(''), isNull);
    expect(parseSubscriptionTraffic(null), isNull);
    expect(parseSubscriptionTraffic('expire=1700000000'), isNull);
    expect(formatSubscriptionTraffic(null, russian: true), '—');
  });

  test('a body comment supplies the header when the response omits it', () {
    const line = 'upload=0; download=1; total=10';
    expect(
      subscriptionTrafficMeta(
        body: '# Teremok VPN\n#subscription-userinfo: $line\nhysteria2://x',
      ),
      line,
    );
    expect(
      subscriptionTrafficMeta(
          header: 'upload=1; download=0; total=2', body: ''),
      'upload=1; download=0; total=2',
    );
  });

  test('an unknown cap does not send a conditional etag', () {
    expect(
      etagUnlessTrafficUnknown(etag: '"abc"', trafficKnown: false),
      isNull,
    );
    expect(
      etagUnlessTrafficUnknown(etag: '"abc"', trafficKnown: true),
      '"abc"',
    );
    expect(hasTrafficSnapshot(null), isFalse);
    expect(hasTrafficSnapshot(''), isFalse);
    expect(hasTrafficSnapshot('upload=0; download=1; total=2'), isTrue);
  });

  test('a missing header keeps the last snapshot', () {
    const saved = 'upload=0; download=1; total=10';
    expect(keptTrafficMeta(observed: null, saved: saved), saved);
    expect(keptTrafficMeta(observed: '', saved: saved), saved);
    expect(
      keptTrafficMeta(observed: 'upload=0; download=2; total=10', saved: saved),
      'upload=0; download=2; total=10',
    );
    expect(keptTrafficMeta(observed: null, saved: null), isNull);
    expect(
      subscriptionTrafficMeta(
        body: 'hysteria2://user:pass@203.0.113.10:443/?sni=a.example#One',
      ),
      isNull,
    );
  });

  test('remainder color bands are above 20, 5 to 20, and below 5 GiB', () {
    SubscriptionTraffic at(int left) {
      return SubscriptionTraffic(upload: 0, download: 0, total: left);
    }

    expect(trafficRemainderBand(at(21 * gib)), TrafficRemainderBand.above20);
    expect(trafficRemainderBand(at(20 * gib)), TrafficRemainderBand.from5to20);
    expect(trafficRemainderBand(at(5 * gib)), TrafficRemainderBand.from5to20);
    expect(trafficRemainderBand(at(5 * gib - 1)), TrafficRemainderBand.below5);
    expect(
      trafficRemainderBand(
          const SubscriptionTraffic(upload: 0, download: 0, total: 0)),
      TrafficRemainderBand.none,
    );
    expect(trafficRemainderBand(null), TrafficRemainderBand.none);
  });
}
