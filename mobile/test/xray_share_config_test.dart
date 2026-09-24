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
    final outbound = (decoded['outbounds'] as List).first as Map;
    expect(outbound['protocol'], 'vless');
    final stream = outbound['streamSettings'] as Map;
    expect(stream['security'], 'reality');
    expect(json.contains('11111111-1111-1111-1111-111111111111'), isTrue);
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

  test('hysteria2 is not an xray document', () {
    const raw = 'hysteria2://user:pass@203.0.113.12:443/?sni=c.example#Charlie';
    expect(buildXraySocksConfig(parseShareLink(raw)), isNull);
  });
}
