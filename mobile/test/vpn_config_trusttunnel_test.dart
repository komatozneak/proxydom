import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/features/vpn/data/vpn_config.dart';
import 'package:teremok_connect/features/vpn/data/vpn_node.dart';

void main() {
  test('parses the golden backend trusttunnel_profile v1 fixture', () {
    final payload = jsonDecode(
      File('test/fixtures/trusttunnel_profile_v1.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final config = VpnConfig.fromJson(payload);

    // Xray profile stays intact alongside the TT profile (dual-core).
    expect(config.xrayProfile.schemaVersion, 2);
    expect(config.xrayProfile.candidates, hasLength(1));

    final tt = config.trusttunnelProfile;
    expect(tt, isNotNull);
    expect(tt!.schemaVersion, 1);
    expect(tt.nodeId, 'al-tirana-tt');
    expect(tt.hostname, 'tt-al.teremokconnect.online');
    expect(tt.addresses, ['tt-al.teremokconnect.online:443']);
    expect(tt.region, 'al');
    expect(tt.purpose, 'youtube');
    expect(tt.username, 'ttu42xdeadbeef');
    expect(tt.password, 'fixture-secret-password');
    expect(tt.upstreamProtocol, 'http2');
    expect(tt.upstreamFallbackProtocol, 'http2');
    expect(tt.antiDpi, isFalse);
    expect(tt.dnsUpstreams, [
      'https://dns.adguard-dns.com/dns-query',
      'https://dns.google/dns-query',
    ]);

    // TOML is passed verbatim to the native VpnClient.
    expect(tt.toml, contains('hostname = "tt-al.teremokconnect.online"'));
    expect(tt.toml, contains('upstream_protocol = "http2"'));
    expect(
      tt.toml,
      contains(
        'dns_upstreams = ["https://dns.adguard-dns.com/dns-query", '
        '"https://dns.google/dns-query"]',
      ),
    );
    expect(tt.toml, contains('mtu_size = 1420'));

    // Round-trip keeps the profile (session restore path).
    final restored = VpnConfig.fromJson(config.toJson());
    expect(restored.trusttunnelProfile, isNotNull);
    expect(restored.trusttunnelProfile!.toml, tt.toml);
  });

  test('trusttunnel_profile absent → null (Xray-only backend)', () {
    final payload = jsonDecode(
      File('test/fixtures/xray_profile_v1.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final config = VpnConfig.fromJson(payload);
    expect(config.trusttunnelProfile, isNull);
  });

  test('incomplete trusttunnel_profile → FormatException', () {
    final payload = jsonDecode(
      File('test/fixtures/trusttunnel_profile_v1.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final tt = payload['trusttunnel_profile'] as Map<String, dynamic>;
    tt['toml'] = '';
    expect(() => VpnConfig.fromJson(payload), throwsFormatException);
  });

  test('TrustTunnelProfile defaults prefer http2 when JSON omits protocols', () {
    final profile = TrustTunnelProfile.fromJson({
      'schema_version': 1,
      'node_id': 'us-youtube-tt',
      'hostname': 'tt-us.teremokconnect.online',
      'addresses': ['45.91.248.91:443'],
      'username': 'u',
      'password': 'p',
      'toml': 'loglevel = "info"\n',
    });
    expect(profile.upstreamProtocol, 'http2');
    expect(profile.upstreamFallbackProtocol, 'http2');
    expect(profile.antiDpi, isFalse);
  });

  test('VpnNode protocol parsing and isTrustTunnel', () {
    final ttNode = VpnNode.fromJson({
      'id': 'al-tirana-tt',
      'label': 'TrustTunnel · tt-al.teremokconnect.online',
      'host': 'tt-al.teremokconnect.online',
      'port': 443,
      'status': 'connected',
      'is_default': false,
      'name': 'al-tirana-tt',
      'protocol': 'trusttunnel',
    });
    expect(ttNode.isTrustTunnel, isTrue);
    expect(ttNode.protocol, kVpnNodeProtocolTrusttunnel);

    final vlessNode = VpnNode.fromJson({
      'id': 'local',
      'host': '204.11.2.216',
      'status': 'connected',
      'is_default': true,
    });
    expect(vlessNode.isTrustTunnel, isFalse);
    expect(vlessNode.protocol, kVpnNodeProtocolVlessReality);

    // Round-trip keeps protocol (node cache persistence).
    final restored = VpnNode.fromJson(ttNode.toJson());
    expect(restored.isTrustTunnel, isTrue);
  });
}
