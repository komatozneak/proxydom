import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/features/vpn/data/share_link_parser.dart';
import 'package:proxydom/features/vpn/data/engine_share_config.dart';

void main() {
  test('vless reality link is refused by the parked engine', () {
    // v2ray-core has no Reality engine, so the builder must not hand the loader
    // a document it will reject (docs/ops/engine-migration/02-reality-spike-findings.md).
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

  test('hysteria2 is not an engine document', () {
    const raw = 'hysteria2://user:pass@203.0.113.12:443/?sni=c.example#Charlie';
    expect(buildShareSocksConfig(parseShareLink(raw)), isNull);
  });
}
