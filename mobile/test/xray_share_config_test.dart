import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/features/vpn/data/share_link_parser.dart';
import 'package:teremok_connect/features/vpn/data/xray_share_config.dart';

void main() {
  test('vless reality config keeps the id and does not describe hy2', () {
    const raw =
        'vless://11111111-1111-1111-1111-111111111111@203.0.113.10:443'
        '?security=reality&sni=www.example.com&pbk=PUBLIC&sid=ab&fp=chrome#Alpha';
    final link = parseShareLink(raw);
    final json = buildXraySocksConfig(link);
    expect(json, isNotNull);
    final decoded = jsonDecode(json!) as Map<String, dynamic>;
    final inbound = (decoded['inbounds'] as List).first as Map;
    expect(inbound['port'], xraySocksPort);
    final outbounds = decoded['outbounds'] as List;
    final outbound = outbounds.first as Map;
    expect(outbound['protocol'], 'vless');
    expect(outbound['tag'], 'proxy');
    expect((outbounds[1] as Map)['tag'], 'direct');
    final stream = outbound['streamSettings'] as Map;
    expect(stream['security'], 'reality');
    final rules = (decoded['routing'] as Map)['rules'] as List;
    expect((rules.first as Map)['outboundTag'], 'direct');
    expect(json.contains('11111111-1111-1111-1111-111111111111'), isTrue);
  });

  test('trojan uses servers, not vnext', () {
    const raw =
        'trojan://secret@203.0.113.10:8445?security=tls&sni=stand.example'
        '&allowInsecure=1#trojan';
    final json = buildXraySocksConfig(parseShareLink(raw));
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
    final json = buildXraySocksConfig(parseShareLink(raw));
    final decoded = jsonDecode(json!) as Map<String, dynamic>;
    final outbound = (decoded['outbounds'] as List).first as Map;
    final tls = (outbound['streamSettings'] as Map)['tlsSettings'] as Map;
    expect(tls['allowInsecure'], isTrue);
  });

  test('vmess kcp carries the seed from path', () {
    const payload = '{"add":"203.0.113.10","port":"10086","id":"11111111-1111-1111-1111-111111111111","net":"kcp","path":"standKcp","tls":""}';
    final raw = 'vmess://${base64Encode(utf8.encode(payload))}';
    final json = buildXraySocksConfig(parseShareLink(raw));
    final decoded = jsonDecode(json!) as Map<String, dynamic>;
    final stream = ((decoded['outbounds'] as List).first as Map)['streamSettings'] as Map;
    expect(stream['network'], 'kcp');
    expect((stream['kcpSettings'] as Map)['seed'], 'standKcp');
  });

  test('hysteria2 is not an xray document', () {
    const raw = 'hysteria2://user:pass@203.0.113.12:443/?sni=c.example#Charlie';
    expect(buildXraySocksConfig(parseShareLink(raw)), isNull);
  });
}
