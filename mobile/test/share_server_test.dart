import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/features/vpn/data/vpn_service_config.dart';

void main() {
  test('a share endpoint splits into host and port', () {
    expect(
        shareServerOf('203.0.113.9:8443'), (host: '203.0.113.9', port: 8443));
    expect(
        shareServerOf('node.example:443'), (host: 'node.example', port: 443));
  });

  test('an IPv6 endpoint splits at the last colon', () {
    // Uri.host drops the brackets, so the endpoint arrives bare.
    expect(shareServerOf('2001:db8::1:443'), (host: '2001:db8::1', port: 443));
    expect(
        shareServerOf('[2001:db8::1]:443'), (host: '2001:db8::1', port: 443));
  });

  test('no usable endpoint is null', () {
    for (final endpoint in [
      null,
      '',
      'node.example',
      ':443',
      'node.example:',
      'h:0',
      'h:70000'
    ]) {
      expect(shareServerOf(endpoint), isNull, reason: '$endpoint');
    }
  });
}
