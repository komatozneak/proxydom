import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/features/vpn/data/share_link_parser.dart';
import 'package:proxydom/features/vpn/data/engine_share_config.dart';

void main() {
  test('vless reality link is refused by the parked engine', () {
    // v2ray-core has no Reality engine, so the builder must not hand the loader
    // a document it will reject.
    const raw =
        'vless://11111111-1111-1111-1111-111111111111@203.0.113.10:443'
        '?security=reality&sni=www.example.com&pbk=PUBLIC&sid=ab&fp=chrome#Alpha';
    final link = parseShareLink(raw);
    expect(buildShareSocksConfig(link), isNull);
  });

  test('vless xhttp link is refused by the parked engine', () {
    const raw =
        'vless://11111111-1111-1111-1111-111111111111@203.0.113.10:443'
        '?security=tls&sni=www.example.com&type=xhttp&path=%2Fx#Xhttp';
    expect(buildShareSocksConfig(parseShareLink(raw)), isNull);
  });

  test('vless tls link keeps the id and describes the engine inbound', () {
    const raw =
        'vless://11111111-1111-1111-1111-111111111111@203.0.113.10:443'
        '?security=tls&sni=www.example.com&fp=chrome#Alpha';
    final json = buildShareSocksConfig(parseShareLink(raw));
    expect(json, isNotNull);
    final decoded = jsonDecode(json!) as Map<String, dynamic>;
    final inbound = (decoded['inbounds'] as List).first as Map;
    expect(inbound['port'], shareSocksPort);
    final outbounds = decoded['outbounds'] as List;
    final outbound = outbounds.first as Map;
    expect(outbound['protocol'], 'vless');
    expect(outbound['tag'], 'proxy');
    expect((outbounds[1] as Map)['tag'], 'direct');
    final stream = outbound['streamSettings'] as Map;
    expect(stream['security'], 'tls');
    expect(stream.containsKey('realitySettings'), isFalse);
    final rules = (decoded['routing'] as Map)['rules'] as List;
    expect((rules.first as Map)['outboundTag'], 'direct');
    expect(json.contains('11111111-1111-1111-1111-111111111111'), isTrue);
  });

  test('trojan uses servers, not vnext', () {
    const raw =
        'trojan://secret@203.0.113.10:8445?security=tls&sni=stand.example'
        '&allowInsecure=1#trojan';
    final json = buildShareSocksConfig(parseShareLink(raw));
    final decoded = jsonDecode(json!) as Map<String, dynamic>;
    final outbound = (decoded['outbounds'] as List).first as Map;
    expect(outbound['protocol'], 'trojan');
    final servers = (outbound['settings'] as Map)['servers'] as List;
    expect((servers.first as Map)['password'], 'secret');
    expect(outbound['settings'].toString().contains('vnext'), isFalse);
  });

  test('allowInsecure=1 is copied into tls settings', () {
    const raw =
        'vless://11111111-1111-1111-1111-111111111111@203.0.113.10:8444'
        '?security=tls&sni=stand.example&type=ws&path=%2Fws&allowInsecure=1#ws';
    final json = buildShareSocksConfig(parseShareLink(raw));
    final decoded = jsonDecode(json!) as Map<String, dynamic>;
    final outbound = (decoded['outbounds'] as List).first as Map;
    final tls = (outbound['streamSettings'] as Map)['tlsSettings'] as Map;
    expect(tls['allowInsecure'], isTrue);
  });

  test('vmess kcp carries the seed from path', () {
    const payload = '{"add":"203.0.113.10","port":"10086","id":"11111111-1111-1111-1111-111111111111","net":"kcp","path":"standKcp","tls":""}';
    final raw = 'vmess://${base64Encode(utf8.encode(payload))}';
    final json = buildShareSocksConfig(parseShareLink(raw));
    final decoded = jsonDecode(json!) as Map<String, dynamic>;
    final stream = ((decoded['outbounds'] as List).first as Map)['streamSettings'] as Map;
    expect(stream['network'], 'kcp');
    expect((stream['kcpSettings'] as Map)['seed'], 'standKcp');
  });

  test('alpn from the link reaches tlsSettings', () {
    const raw =
        'vless://11111111-1111-1111-1111-111111111111@203.0.113.10:2083'
        '?security=tls&sni=front.example&type=ws&path=%2Fvless-ws'
        '&alpn=http%2F1.1&fp=chrome#WS';
    final json = buildShareSocksConfig(parseShareLink(raw));
    final decoded = jsonDecode(json!) as Map<String, dynamic>;
    final stream =
        ((decoded['outbounds'] as List).first as Map)['streamSettings'] as Map;
    expect(stream['network'], 'ws');
    expect((stream['wsSettings'] as Map)['path'], '/vless-ws');
    final tls = stream['tlsSettings'] as Map;
    expect(tls['serverName'], 'front.example');
    // `fp=chrome` is not a v2ray-core uTLS preset. The builder translates it.
    expect(tls['fingerprint'], 'chrome_auto');
    // A front that serves only http/1.1 refuses a WS upgrade offered under h2.
    expect(tls['alpn'], ['http/1.1']);
  });

  test('a multi-value alpn list is split, and its absence stays absent', () {
    const withList =
        'vless://11111111-1111-1111-1111-111111111111@203.0.113.10:443'
        '?security=tls&sni=a.example&alpn=h2,http%2F1.1#A';
    final decoded = jsonDecode(buildShareSocksConfig(parseShareLink(withList))!)
        as Map<String, dynamic>;
    final tls = (((decoded['outbounds'] as List).first as Map)['streamSettings']
        as Map)['tlsSettings'] as Map;
    expect(tls['alpn'], ['h2', 'http/1.1']);

    const without =
        'vless://11111111-1111-1111-1111-111111111111@203.0.113.10:443'
        '?security=tls&sni=a.example#A';
    final plain = jsonDecode(buildShareSocksConfig(parseShareLink(without))!)
        as Map<String, dynamic>;
    final plainTls =
        (((plain['outbounds'] as List).first as Map)['streamSettings']
            as Map)['tlsSettings'] as Map;
    expect(plainTls.containsKey('alpn'), isFalse);
  });

  test('an unknown fingerprint is omitted rather than sent to the core', () {
    const raw =
        'vless://11111111-1111-1111-1111-111111111111@203.0.113.10:443'
        '?security=tls&sni=a.example&fp=not-a-preset#A';
    final decoded = jsonDecode(buildShareSocksConfig(parseShareLink(raw))!)
        as Map<String, dynamic>;
    final tls = (((decoded['outbounds'] as List).first as Map)['streamSettings']
        as Map)['tlsSettings'] as Map;
    expect(tls.containsKey('fingerprint'), isFalse);
  });

  test('hysteria2 is not an engine document', () {
    const raw = 'hysteria2://user:pass@203.0.113.12:443/?sni=c.example#Charlie';
    expect(buildShareSocksConfig(parseShareLink(raw)), isNull);
  });

  // The loader accepts only tcp, websocket and mkcp. Offering anything else as
  // active means the user taps the line and the start fails with no name.
  test('transports the loader cannot express are refused', () {
    for (final transport in const [
      'grpc',
      'quic',
      'httpupgrade',
      'xhttp',
      'splithttp',
    ]) {
      final raw =
          'vless://11111111-1111-1111-1111-111111111111@203.0.113.10:443'
          '?security=tls&sni=a.example&type=$transport#T';
      expect(
        buildShareSocksConfig(parseShareLink(raw)),
        isNull,
        reason: 'type=$transport must not reach the loader',
      );
    }
  });

  // shareStreamConfig() rejects every security except none and tls.
  test('securities the loader cannot express are refused', () {
    for (final security in const ['xtls', 'reality']) {
      final raw =
          'vless://11111111-1111-1111-1111-111111111111@203.0.113.10:443'
          '?security=$security&sni=a.example#S';
      expect(
        buildShareSocksConfig(parseShareLink(raw)),
        isNull,
        reason: 'security=$security must not reach the loader',
      );
    }
  });

  // The loader has no tcpSettings, so HTTP obfuscation cannot be expressed.
  // Dropping it would dial plain TCP and report a generic failure.
  test('tcp obfuscation is refused rather than silently dropped', () {
    const http =
        'vless://11111111-1111-1111-1111-111111111111@203.0.113.10:80'
        '?security=none&type=tcp&headerType=http&host=cdn.example#Obfs';
    expect(buildShareSocksConfig(parseShareLink(http)), isNull);

    // `headerType=none` asks for no obfuscation and must still build.
    const none =
        'vless://11111111-1111-1111-1111-111111111111@203.0.113.10:80'
        '?security=none&type=tcp&headerType=none#Plain';
    expect(buildShareSocksConfig(parseShareLink(none)), isNotNull);
  });

  // Guards the allowlist against over-refusing: every transport and security
  // the loader does express must still produce a document.
  test('every transport and security the loader expresses still builds', () {
    for (final transport in const ['tcp', 'ws', 'websocket', 'kcp']) {
      final raw =
          'vless://11111111-1111-1111-1111-111111111111@203.0.113.10:443'
          '?security=tls&sni=a.example&type=$transport&path=%2Fp#T';
      final json = buildShareSocksConfig(parseShareLink(raw));
      expect(json, isNotNull, reason: 'type=$transport must build');
      final outbound =
          (jsonDecode(json!) as Map<String, dynamic>)['outbounds'] as List;
      expect(
        ((outbound.first as Map)['streamSettings'] as Map)['network'],
        transport == 'websocket' ? 'websocket' : transport,
      );
    }
    for (final security in const ['none', 'tls']) {
      final raw =
          'vless://11111111-1111-1111-1111-111111111111@203.0.113.10:443'
          '?security=$security&sni=a.example#S';
      expect(
        buildShareSocksConfig(parseShareLink(raw)),
        isNotNull,
        reason: 'security=$security must build',
      );
    }
  });

  // A WS front is reached by Host, not by the address in the link.
  test('the ws Host header from the link survives into wsSettings', () {
    const raw =
        'vless://11111111-1111-1111-1111-111111111111@203.0.113.10:443'
        '?security=tls&sni=front.example&type=ws&path=%2Fws'
        '&host=cdn.example#WS';
    final json = buildShareSocksConfig(parseShareLink(raw))!;
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    final stream =
        ((decoded['outbounds'] as List).first as Map)['streamSettings'] as Map;
    expect((stream['wsSettings'] as Map)['headers'], {'Host': 'cdn.example'});
  });

  // Share links are hand-written and generator-written, so `type=WS` and
  // `security=TLS` reach the parser as often as the lowercase forms. The C++
  // broker and the Go loader both fold case before their own checks, and the
  // `headerType` rule here always did; comparing the raw word made this the one
  // side that refused, and it refused on every platform at once — a node the
  // engine can dial shown as unsupported.
  test('transport and security names are matched case-insensitively', () {
    Map<String, Object?> streamOf(String raw) {
      final json = buildShareSocksConfig(parseShareLink(raw));
      expect(json, isNotNull, reason: '$raw must build');
      final decoded = jsonDecode(json!) as Map<String, dynamic>;
      final outbound = (decoded['outbounds'] as List).first as Map;
      return outbound['streamSettings'] as Map<String, Object?>;
    }

    String link({String? type, String? security}) =>
        'vless://11111111-1111-1111-1111-111111111111@203.0.113.10:443'
        '?sni=a.example'
        '${type == null ? '' : '&type=$type'}'
        '${security == null ? '' : '&security=$security'}#C';

    // Folded, and the document carries the folded word: the core's own names
    // are lowercase, so passing `WS` through would be a second bug.
    for (final written in const ['ws', 'WS', 'Ws', 'wS']) {
      expect(
        streamOf(link(type: written, security: 'tls'))['network'],
        'ws',
        reason: 'type=$written must fold to ws',
      );
    }
    for (final written in const ['tls', 'TLS', 'Tls']) {
      final stream = streamOf(link(security: written));
      expect(stream['security'], 'tls', reason: 'security=$written must fold');
      expect(stream.containsKey('tlsSettings'), isTrue);
    }
    for (final written in const ['none', 'NONE', 'None']) {
      final stream = streamOf(link(security: written));
      expect(stream['security'], 'none', reason: 'security=$written must fold');
      expect(
        stream.containsKey('tlsSettings'),
        isFalse,
        reason: 'security=$written must not ask for TLS',
      );
    }
    // `mkcp` is folded before the alias table is consulted, so the alias still
    // applies; `MKCP` is the same word written loudly.
    for (final written in const ['mkcp', 'MKCP', 'kcp', 'KCP']) {
      expect(
        streamOf(link(type: written, security: 'tls'))['network'],
        'kcp',
        reason: 'type=$written must fold to kcp',
      );
    }
    // Refusals stay refusals however they are capitalised: folding must not
    // widen the allowlist.
    for (final written in const ['GRPC', 'Grpc', 'XHTTP', 'QUIC']) {
      expect(
        buildShareSocksConfig(parseShareLink(link(type: written, security: 'tls'))),
        isNull,
        reason: 'type=$written must stay refused',
      );
    }
    for (final written in const ['REALITY', 'Reality', 'XTLS', 'Xtls']) {
      expect(
        buildShareSocksConfig(parseShareLink(link(security: written))),
        isNull,
        reason: 'security=$written must stay refused',
      );
    }
  });
}
