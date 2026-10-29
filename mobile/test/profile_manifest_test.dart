import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/features/vpn/data/profile_manifest.dart';

String _encode(Map<String, Object?> value) {
  return base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
}

Map<String, Object?> _profile({
  Object? version = 1,
  Map<String, Object?>? traffic,
  Map<String, Object?> extra = const {},
}) {
  return {
    'version': version,
    'displayName': 'Терем',
    'description': 'Поддержка в Telegram',
    'supportUrl': 'https://t.me/example_support',
    'supportLabel': 'Поддержка',
    'planName': '100 GB',
    'accent': '#8A6A2F',
    if (traffic != null) 'traffic': traffic,
    ...extra,
  };
}

void main() {
  group('decodeProfileManifest', () {
    test('reads a complete profile and its quota', () {
      final value = _encode(_profile(
        traffic: {
          'upload': 0,
          'download': 27000000000,
          'total': 100000000000,
          'unlimited': false,
          'updatedAt': '2026-10-29T09:00:00Z',
        },
      ));

      final manifest = decodeProfileManifest(value);
      expect(manifest, isNotNull);
      expect(manifest!.displayName, 'Терем');
      expect(manifest.supportUrl, 'https://t.me/example_support');
      expect(manifest.planName, '100 GB');
      expect(manifest.traffic!.download, 27000000000);
      expect(manifest.traffic!.total, 100000000000);
      expect(manifest.traffic!.updatedAt, DateTime.utc(2026, 10, 29, 9));
    });

    test('accepts standard base64 and padding too', () {
      final standard = base64.encode(
        utf8.encode(jsonEncode(_profile())),
      );
      expect(decodeProfileManifest(standard), isNotNull);
    });

    test('rejects a BOM, a bad version and malformed base64', () {
      final bom = base64.encode([
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode(jsonEncode(_profile())),
      ]);
      expect(decodeProfileManifest(bom), isNull);
      expect(decodeProfileManifest(_encode(_profile(version: 0))), isNull);
      expect(decodeProfileManifest(_encode(_profile(version: '1'))), isNull);
      expect(decodeProfileManifest('not base64 !!!'), isNull);
      expect(decodeProfileManifest(''), isNull);
    });

    test('continues to read known keys from a future version', () {
      final manifest = decodeProfileManifest(_encode(_profile(version: 2)));
      expect(manifest, isNotNull);
      expect(manifest!.version, 2);
      expect(manifest.displayName, 'Терем');
    });

    test('drops a bad optional field but keeps the card', () {
      final manifest = decodeProfileManifest(_encode(_profile(
        extra: {
          'supportUrl': 'http://example.com',
          'accent': 'red',
        },
      )));
      expect(manifest, isNotNull);
      expect(manifest!.supportUrl, isNull);
      expect(manifest.accent, isNull);
    });

    test('truncates text to the scalar limits', () {
      final manifest = decodeProfileManifest(_encode(_profile(extra: {
        'displayName': 'Я' * 50,
        'description': 'Первая\nВторая\nТретья',
      })));
      expect(manifest, isNotNull);
      expect(manifest!.displayName!.runes.length, 40);
      expect(manifest.description, 'Первая\nВторая');
    });

    test('rejects an unbounded object', () {
      final extra = <String, Object?>{
        for (var i = 0; i < 17; i++) 'unknown$i': i,
      };
      expect(
        decodeProfileManifest(_encode(_profile(extra: extra))),
        isNull,
      );
    });

    test('rejects too deep a nest', () {
      final extra = <String, Object?>{
        'a': {
          'b': {
            'c': {
              'd': {'e': 1},
            },
          },
        },
      };
      expect(
        decodeProfileManifest(_encode(_profile(extra: extra))),
        isNull,
      );
    });

    test('parses traffic states without inventing a cap', () {
      final unlimited = decodeProfileManifest(_encode(_profile(
        traffic: {
          'unlimited': true,
          'download': 123456789,
        },
      )));
      expect(unlimited!.traffic!.unlimited, isTrue);
      expect(unlimited.traffic!.total, isNull);

      final zero = decodeProfileManifest(_encode(_profile(
        traffic: {'total': 0, 'upload': 0},
      )));
      expect(zero!.traffic!.total, 0);
      expect(zero.traffic!.unlimited, isFalse);

      final usedOnly = decodeProfileManifest(_encode(_profile(
        traffic: {'download': 27},
      )));
      expect(usedOnly!.traffic!.total, isNull);
      expect(usedOnly.traffic!.usedBytes, 27);
    });

    test('drops the traffic block when a numeric field is invalid', () {
      final manifest = decodeProfileManifest(_encode(_profile(
        traffic: {'total': 100, 'upload': -1},
      )));
      expect(manifest, isNotNull);
      expect(manifest!.traffic, isNull);
    });

    test('requires an explicit offset on dates', () {
      final manifest = decodeProfileManifest(_encode(_profile(
        traffic: {
          'total': 100,
          'resetAt': '2026-11-01T00:00:00',
        },
      )));
      expect(manifest!.traffic!.resetAt, isNull);
    });
  });

  group('profileManifestFromResponse', () {
    test('the header wins over the body', () {
      final header = _encode(_profile(extra: {'displayName': 'Header'}));
      final body = '#proxydom-profile: '
          '${_encode(_profile(extra: {'displayName': 'Body'}))}\n'
          'hysteria2://u:p@example.com:443#Node';
      final manifest = profileManifestFromResponse(
        header: header,
        body: body,
      );
      expect(manifest!.displayName, 'Header');
    });

    test('a broken header does not fall back to the body', () {
      final body = '#proxydom-profile: '
          '${_encode(_profile(extra: {'displayName': 'Body'}))}\n';
      expect(
        profileManifestFromResponse(header: 'broken', body: body),
        isNull,
      );
    });

    test('the body is used when the header is absent', () {
      final body = '#proxydom-profile: '
          '${_encode(_profile(extra: {'displayName': 'Body'}))}\n';
      expect(
        profileManifestFromResponse(body: body)!.displayName,
        'Body',
      );
    });
  });
}
