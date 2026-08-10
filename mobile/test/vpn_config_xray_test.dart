import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/features/vpn/data/vpn_config.dart';

Map<String, dynamic> _candidate({
  required String id,
  required String host,
  required int port,
  required String uuid,
  required String transport,
}) =>
    {
      'id': id,
      'label': 'Node $id',
      'host': host,
      'port': port,
      'protocol': 'vless',
      'uuid': uuid,
      'flow': id == 'a' ? 'xtls-rprx-vision' : null,
      'transport': transport,
      'security': 'reality',
      'server_name': '$id.example',
      'public_key': 'pk-$id',
      'short_id': 'short-$id',
      'fingerprint': id == 'a' ? 'chrome' : 'firefox',
      'spider_x': '/$id',
    };

Map<String, dynamic> _response(Map<String, dynamic> xrayProfile) => {
      'username': 'test-user',
      'links': const <String>[],
      'expire': 1785654092,
      'xray_profile': xrayProfile,
    };

void main() {
  test('parses the golden backend xray_profile v1 fixture', () {
    final payload = jsonDecode(
      File('test/fixtures/xray_profile_v1.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final config = VpnConfig.fromJson(payload);

    expect(config.xrayProfile.schemaVersion, 1);
    expect(config.egressHosts, ['203.0.113.10', '203.0.113.20']);
    expect(config.expectedEgressHost, '203.0.113.10');
    expect(config.xrayProfile.candidates[0].flow, 'xtls-rprx-vision');
    expect(config.xrayProfile.candidates[1].port, 8443);
    expect(config.xrayProfile.candidates[1].transport, 'raw');
  });

  test('parses complete candidate-specific Xray settings', () {
    final config = VpnConfig.fromJson(
      _response({
        'schema_version': 1,
        'candidates': [
          _candidate(
            id: 'a',
            host: '1.2.3.4',
            port: 443,
            uuid: 'uuid-a',
            transport: 'tcp',
          ),
          _candidate(
            id: 'b',
            host: '5.6.7.8',
            port: 8443,
            uuid: 'uuid-b',
            transport: 'raw',
          ),
        ],
      }),
    );

    expect(config.xrayProfile.schemaVersion, 1);
    expect(config.xrayProfile.candidates, hasLength(2));
    final second = config.xrayProfile.candidates[1];
    expect(second.host, '5.6.7.8');
    expect(second.port, 8443);
    expect(second.uuid, 'uuid-b');
    expect(second.flow, isNull);
    expect(second.transport, 'raw');
    expect(second.serverName, 'b.example');
    expect(second.spiderX, '/b');
    expect(config.egressHosts, ['1.2.3.4', '5.6.7.8']);
  });

  test('requires xray_profile or vless fallback and supported schema', () {
    expect(
      () => VpnConfig.fromJson({
        'username': 'test-user',
        'links': const <String>[],
        'expire': 1785654092,
      }),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => VpnConfig.fromJson(
        _response({
          'schema_version': 3,
          'candidates': [
            _candidate(
              id: 'a',
              host: '1.2.3.4',
              port: 443,
              uuid: 'uuid-a',
              transport: 'tcp',
            ),
          ],
        }),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('schema v2 candidates carry region/purpose for YT routing', () {
    final config = VpnConfig.fromJson(
      _response({
        'schema_version': 2,
        'candidates': [
          {
            ..._candidate(
              id: 'a',
              host: '1.2.3.4',
              port: 443,
              uuid: 'uuid-a',
              transport: 'tcp',
            ),
            'region': 'al',
            'purpose': 'youtube',
          },
        ],
      }),
    );
    expect(config.xrayProfile.schemaVersion, 2);
    expect(config.xrayProfile.candidates.single.region, 'al');
    expect(config.xrayProfile.candidates.single.purpose, 'youtube');
  });

  test('falls back to selected_link when xray_profile is missing', () {
    const link =
        'vless://11111111-2222-3333-4444-555555555555@203.0.113.10:443'
        '?encryption=none&flow=xtls-rprx-vision&security=reality'
        '&sni=cover.example&fp=chrome&pbk=fixture-public-key'
        '&sid=deadbeef&spx=%2F&type=tcp#Germany';
    final config = VpnConfig.fromJson({
      'username': 'test-user',
      'links': const <String>[],
      'selected_link': link,
      'expire': 1785654092,
      'node_host': '203.0.113.10',
    });

    expect(config.xrayProfile.schemaVersion, 1);
    expect(config.xrayProfile.candidates, hasLength(1));
    final candidate = config.xrayProfile.candidates.single;
    expect(candidate.host, '203.0.113.10');
    expect(candidate.uuid, '11111111-2222-3333-4444-555555555555');
    expect(candidate.serverName, 'cover.example');
    expect(candidate.publicKey, 'fixture-public-key');
    expect(candidate.shortId, 'deadbeef');
    expect(candidate.flow, 'xtls-rprx-vision');
    expect(config.expectedEgressHost, '203.0.113.10');
  });

  test('falls back to first links[] vless when selected_link absent', () {
    const link =
        'vless://aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee@198.51.100.7:8443'
        '?security=reality&sni=second.example&fp=firefox&pbk=pk2'
        '&sid=cafebabe&type=raw#NL';
    final config = VpnConfig.fromJson({
      'username': 'test-user',
      'links': <String>['https://ignored.example', link],
      'expire': 1785654092,
    });
    expect(config.xrayProfile.candidates.single.host, '198.51.100.7');
    expect(config.xrayProfile.candidates.single.port, 8443);
    expect(config.xrayProfile.candidates.single.transport, 'raw');
  });

  test('fills empty sid from legacy sing_box_config when xray_profile absent',
      () {
    const link =
        'vless://11111111-2222-3333-4444-555555555555@203.0.113.10:443'
        '?encryption=none&flow=xtls-rprx-vision&security=reality'
        '&sni=cover.example&fp=chrome&pbk=fixture-public-key'
        '&sid=&type=tcp#Germany';
    final config = VpnConfig.fromJson({
      'username': 'test-user',
      'links': const <String>[],
      'selected_link': link,
      'expire': 1785654092,
      'sing_box_config': {
        'outbounds': [
          {
            'type': 'vless',
            'server': '203.0.113.10',
            'tls': {
              'server_name': 'cover.example',
              'reality': {
                'public_key': 'fixture-public-key',
                'short_id': '5d578915',
              },
            },
          },
        ],
      },
    });
    expect(config.xrayProfile.candidates.single.shortId, '5d578915');
    expect(config.xrayProfile.candidates.single.publicKey, 'fixture-public-key');
  });

  test('prefers xray_profile over legacy sing-box data', () {
    final valid = _response({
      'schema_version': 1,
      'candidates': [
        _candidate(
          id: 'a',
          host: '1.2.3.4',
          port: 443,
          uuid: 'uuid-a',
          transport: 'tcp',
        ),
      ],
    })
      ..['sing_box_config'] = {
        'outbounds': [
          {'type': 'vless', 'server': 'legacy.invalid'},
        ],
      };
    expect(VpnConfig.fromJson(valid).expectedEgressHost, '1.2.3.4');

    final incomplete = _candidate(
      id: 'a',
      host: '1.2.3.4',
      port: 443,
      uuid: 'uuid-a',
      transport: 'tcp',
    )..['public_key'] = '';
    expect(
      () => VpnConfig.fromJson(
        _response({
          'schema_version': 1,
          'candidates': [incomplete],
        }),
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
