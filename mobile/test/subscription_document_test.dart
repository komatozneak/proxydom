import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/features/vpn/data/hy2_import_store.dart';
import 'package:teremok_connect/features/vpn/data/hy2_link_parser.dart';

void main() {
  test('https document keeps the fragment as a fallback title', () {
    final target = subscriptionDocumentTarget(
      'https://sub.example.org/export.txt#My%20Group',
    );
    expect(target, isNotNull);
    expect(target!.url, 'https://sub.example.org/export.txt');
    expect(target.title, 'My Group');
    expect(looksLikeSubscriptionUrl('https://sub.example.org/export.txt'), isTrue);
  });

  test('http document is a subscription address too', () {
    final target = subscriptionDocumentTarget(
      'http://95.182.81.27:8080/sub.txt#Stand',
    );
    expect(target, isNotNull);
    expect(target!.url, 'http://95.182.81.27:8080/sub.txt');
    expect(target.title, 'Stand');
    expect(
      looksLikeSubscriptionUrl('http://95.182.81.27:8080/sub.txt'),
      isTrue,
    );
  });

  test('deeplinks unwrap to the same https document', () {
    const https = 'https://sub.example.org/export.txt';
    final encoded = base64Encode(utf8.encode(https));
    final samples = [
      'happ://add/$https',
      'teremok://import?url=https%3A%2F%2Fsub.example.org%2Fexport.txt',
      'happ://sub/$encoded',
    ];
    for (final raw in samples) {
      expect(subscriptionDocumentTarget(raw)?.url, https, reason: raw);
    }
    expect(
      subscriptionDocumentTarget(
        'teremok://add/http://95.182.81.27:8080/sub.txt',
      )?.url,
      'http://95.182.81.27:8080/sub.txt',
    );
    expect(
      subscriptionDocumentTarget('vless://u@203.0.113.10:443#A'),
      isNull,
    );
  });

  test('refresh keeps a route that is still in the list', () {
    final catalogs = [
      const ShareCatalog(
        id: 'other',
        title: 'Other',
        lines: ['vless://u@203.0.113.1:443#A'],
      ),
      const ShareCatalog(
        id: 'doc',
        title: 'Doc',
        lines: [
          'vless://u@203.0.113.2:443#B',
          'vmess://blob#C',
        ],
      ),
    ];
    expect(
      shareRefreshIndex(
        catalogs: catalogs,
        catalogId: 'doc',
        key: 'vless|203.0.113.2:443',
        owned: false,
      ),
      1,
    );
    expect(
      shareRefreshIndex(
        catalogs: catalogs,
        catalogId: 'doc',
        key: null,
        owned: true,
      ),
      1,
    );
  });

  test('share copies the document address, or the pasted lines', () {
    expect(
      const ShareCatalog(
        id: 'doc',
        title: 'Teremok',
        lines: ['hysteria2://secret@10.0.0.1:443#A'],
        url: 'https://sub.example.org/hs4gGfjG',
      ).subscriptionKey,
      'https://sub.example.org/hs4gGfjG',
    );
    expect(
      const ShareCatalog(
        id: 'paste',
        title: 'One',
        lines: ['  hysteria2://secret@10.0.0.2:443#B  '],
      ).subscriptionKey,
      'hysteria2://secret@10.0.0.2:443#B',
    );
  });
}
