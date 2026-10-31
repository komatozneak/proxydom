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

  test('the parked set is only what no engine here can dial', () {
    // Named rather than inferred: a scheme that gains an engine has to leave
    // this set in the same commit, or the badge keeps saying "unsupported" for
    // a line that starts.
    expect(kParkedSchemes, {'wireguard', 'amneziawg', 'vpn'});
  });

  test('VLESS is admitted wherever the in-process core runs', () {
    expect(canDialSchemeOn(DialTarget.android, 'vless'), isTrue);
    expect(canDialSchemeOn(DialTarget.windows, 'vless'), isTrue);
    expect(canDialSchemeOn(DialTarget.ios, 'vless'), isTrue);
    expect(canDialSchemeOn(DialTarget.other, 'vless'), isFalse);
    expect(windowsDialScheme('vless'), isTrue);
    expect(windowsDialScheme('hysteria2'), isTrue);
    expect(windowsDialScheme('hy2'), isTrue);
  });

  // One in-process core carries the whole v2ray family. A protocol the engine
  // builds a document for and the gate still refuses is the least useful kind
  // of gap: the key imports, the row looks active, and the start is what fails.
  test('VMess, Trojan, Shadowsocks and SOCKS5 follow the core, not the scheme',
      () {
    for (final scheme in ['vmess', 'trojan', 'ss', 'socks5', 'socks']) {
      expect(canDialSchemeOn(DialTarget.android, scheme), isTrue,
          reason: scheme);
      expect(canDialSchemeOn(DialTarget.windows, scheme), isTrue,
          reason: scheme);
      expect(canDialSchemeOn(DialTarget.ios, scheme), isTrue, reason: scheme);
      expect(canDialSchemeOn(DialTarget.other, scheme), isFalse,
          reason: scheme);
      expect(windowsDialScheme(scheme), isTrue, reason: scheme);
    }
  });

  test('a socks5 key reaches the engine builder', () {
    final link = parseShareLink('socks5://1.2.3.4:1080#S');
    expect(link.scheme, 'socks5');
    expect(link.endpoint, '1.2.3.4:1080');
    expect(canDialLinkOn(DialTarget.android, link), isTrue);
    expect(canDialLinkOn(DialTarget.windows, link), isTrue);
    expect(canDialLinkOn(DialTarget.ios, link), isTrue);
  });

  test('a vmess key is admitted and a wireguard key is not', () {
    final vmess = parseShareLink(
      'vmess://eyJhZGQiOiIxLjIuMy40IiwicG9ydCI6NDQzLCJpZCI6InUifQ==',
    );
    expect(canDialLinkOn(DialTarget.android, vmess), isTrue);
    expect(canDialLinkOn(DialTarget.windows, vmess), isTrue);
    expect(canDialLinkOn(DialTarget.ios, vmess), isTrue);
    for (final parked in [
      'wireguard://key@1.2.3.4:51820',
      'amneziawg://key@1.2.3.4:51820',
      'vpn://doc',
    ]) {
      expect(() => parseShareLink(parked), throwsFormatException,
          reason: parked);
    }
  });

  test('case and surrounding whitespace do not decide the gate', () {
    expect(canDialSchemeOn(DialTarget.android, ' VLESS '), isTrue);
    expect(canDialSchemeOn(DialTarget.ios, ' Vless '), isTrue);
    expect(canDialSchemeOn(DialTarget.windows, ' HY2 '), isTrue);
    expect(canDialSchemeOn(DialTarget.android, ' Trojan '), isTrue);
    expect(canDialSchemeOn(DialTarget.android, ' VMESS '), isTrue);
    expect(canDialSchemeOn(DialTarget.android, ' SS '), isTrue);
    expect(canDialSchemeOn(DialTarget.ios, ' Trojan '), isTrue);
    expect(canDialSchemeOn(DialTarget.android, ' WireGuard '), isFalse);
  });

  test('a vless Reality line passes canDialLink where the REALITY engine runs', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const raw =
        'vless://11111111-1111-1111-1111-111111111111@203.0.113.10:443'
        '?security=reality&sni=www.example.com&pbk=PUBLIC&sid=ab&fp=chrome#R';
    final link = parseShareLink(raw);
    expect(canDialSchemeOn(DialTarget.android, link.scheme), isTrue);
    expect(canDialLinkOn(DialTarget.android, link), isTrue);
    expect(canDialLinkOn(DialTarget.windows, link), isTrue);
    expect(canDialLinkOn(DialTarget.ios, link), isTrue);
    expect(canDialLinkOn(DialTarget.other, link), isFalse);
    expect(canDialLink(link), isTrue);
  });

  test('a Reality line over WebSocket stays inactive', () {
    const raw =
        'vless://11111111-1111-1111-1111-111111111111@203.0.113.10:443'
        '?security=reality&pbk=PUBLIC&type=ws&path=%2Fws&sni=front.example#RW';
    final link = parseShareLink(raw);
    expect(canDialLinkOn(DialTarget.android, link), isFalse);
    expect(canDialLinkOn(DialTarget.windows, link), isFalse);
  });

  test('a vless WS/TLS line passes canDialLink only where the engine runs', () {
    const raw =
        'vless://11111111-1111-1111-1111-111111111111@203.0.113.10:443'
        '?security=tls&type=ws&path=%2Fws&sni=front.example#A';
    final link = parseShareLink(raw);
    expect(canDialLinkOn(DialTarget.android, link), isTrue);
    expect(canDialLinkOn(DialTarget.windows, link), isTrue);
    expect(canDialLinkOn(DialTarget.ios, link), isTrue);
    expect(canDialLinkOn(DialTarget.other, link), isFalse);

    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(canDialScheme(link.scheme), isTrue);
    expect(canDialLink(link), isTrue);

    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(canDialLink(link), isTrue);

    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(canDialLink(link), isTrue);
  });

  // gRPC and HTTPUpgrade are dialers the in-process core registers, so a line
  // that carries them is a working line: refusing it would hide a node the
  // engine can start.
  test('a vless gRPC line is dialable where the core runs', () {
    const raw =
        'vless://11111111-1111-1111-1111-111111111111@203.0.113.10:443'
        '?security=tls&type=grpc&serviceName=grpc&sni=front.example#G';
    final link = parseShareLink(raw);
    expect(canDialSchemeOn(DialTarget.windows, link.scheme), isTrue);
    expect(canDialLinkOn(DialTarget.windows, link), isTrue);
    expect(canDialLinkOn(DialTarget.android, link), isTrue);
    expect(canDialLinkOn(DialTarget.ios, link), isTrue);
  });

  // XHTTP is the one that arrived with Xray only. Nothing in this build can
  // dial it, so the line stays a neutral badge instead of a failed start.
  test('a vless XHTTP line stays inactive', () {
    const raw =
        'vless://11111111-1111-1111-1111-111111111111@203.0.113.10:443'
        '?security=tls&type=xhttp&path=%2Fx&sni=front.example#X';
    final link = parseShareLink(raw);
    expect(canDialSchemeOn(DialTarget.windows, link.scheme), isTrue);
    expect(canDialLinkOn(DialTarget.windows, link), isFalse);
    expect(canDialLinkOn(DialTarget.android, link), isFalse);
  });
}
