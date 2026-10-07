import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/features/vpn/data/dial_set.dart';
import 'package:proxydom/features/vpn/data/share_link_parser.dart';

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('Hysteria2 is dialable on every target; parked schemes are not', () {
    for (final target in DialTarget.values) {
      expect(canDialSchemeOn(target, 'hysteria2'), isTrue, reason: '$target');
      expect(canDialSchemeOn(target, 'hy2'), isTrue, reason: '$target');
      for (final parked in kParkedSchemes) {
        expect(
          canDialSchemeOn(target, parked),
          isFalse,
          reason: '$target $parked',
        );
      }
    }
  });

  test('VLESS is admitted on Android and refused on iOS and Windows', () {
    expect(canDialSchemeOn(DialTarget.android, 'vless'), isTrue);
    expect(canDialSchemeOn(DialTarget.ios, 'vless'), isFalse);
    expect(canDialSchemeOn(DialTarget.windows, 'vless'), isFalse);
    expect(canDialSchemeOn(DialTarget.other, 'vless'), isFalse);
    expect(windowsDialScheme('vless'), isFalse);
    expect(windowsDialScheme('hysteria2'), isTrue);
    expect(windowsDialScheme('hy2'), isTrue);
  });

  test('case and surrounding whitespace do not decide the gate', () {
    expect(canDialSchemeOn(DialTarget.android, ' VLESS '), isTrue);
    expect(canDialSchemeOn(DialTarget.ios, ' Vless '), isFalse);
    expect(canDialSchemeOn(DialTarget.windows, ' HY2 '), isTrue);
    expect(canDialSchemeOn(DialTarget.android, ' Trojan '), isFalse);
    expect(canDialSchemeOn(DialTarget.android, ' VMESS '), isFalse);
    expect(canDialSchemeOn(DialTarget.android, ' SS '), isFalse);
  });

  test('a vless Reality line does not pass canDialLink on Android', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const raw =
        'vless://11111111-1111-1111-1111-111111111111@203.0.113.10:443'
        '?security=reality&sni=www.example.com&pbk=PUBLIC&sid=ab&fp=chrome#R';
    final link = parseShareLink(raw);
    expect(canDialSchemeOn(DialTarget.android, link.scheme), isTrue);
    expect(canDialLinkOn(DialTarget.android, link), isFalse);
    expect(canDialLink(link), isFalse);
    for (final target in DialTarget.values) {
      expect(canDialLinkOn(target, link), isFalse, reason: '$target');
    }
  });

  test('a vless WS/TLS line passes canDialLink only on Android', () {
    const raw =
        'vless://11111111-1111-1111-1111-111111111111@203.0.113.10:443'
        '?security=tls&type=ws&path=%2Fws&sni=front.example#A';
    final link = parseShareLink(raw);
    expect(canDialLinkOn(DialTarget.android, link), isTrue);
    expect(canDialLinkOn(DialTarget.ios, link), isFalse);
    expect(canDialLinkOn(DialTarget.windows, link), isFalse);
    expect(canDialLinkOn(DialTarget.other, link), isFalse);

    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(canDialScheme(link.scheme), isTrue);
    expect(canDialLink(link), isTrue);

    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(canDialLink(link), isFalse);
  });
}
