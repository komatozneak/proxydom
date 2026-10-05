import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/features/vpn/data/hy2_import_store.dart';
import 'package:proxydom/features/vpn/data/hy2_link_parser.dart';

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
      'proxydom://add/$https',
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

  test('a reload of another list keeps the chosen key', () {
    // The owner's own shape: one subscription document with four nodes, and one
    // key pasted by hand, which is what the tunnel was actually running.
    const document = ShareCatalog(
      id: 'doc',
      title: 'Teremok',
      url: 'https://sub.proxydom.su/2aq93K0svSy2IRUj',
      lines: [
        'hysteria2://pw@203.0.113.1:443#YouTube',
        'hysteria2://pw@203.0.113.2:443#Индия',
        'hysteria2://pw@203.0.113.3:443#Игровой',
        'hysteria2://pw@203.0.113.4:443#США',
      ],
    );
    const pasted = ShareCatalog(
      id: 'paste',
      title: 'hy2test',
      lines: ['hysteria2://pw@203.0.113.9:443#hy2test'],
    );
    const chosen = 'hysteria2|203.0.113.9:443';

    // Reloading the document, which does not own the chosen key: the choice is
    // the person's, not the document's, and it survives.
    expect(
      selectionAfterReload(
        catalogs: const [document, pasted],
        before: document,
        catalogId: 'doc',
        key: chosen,
      ),
      4,
    );

    // A document that did own the key and lost it lands on its own first row.
    expect(
      selectionAfterReload(
        catalogs: const [pasted],
        before: document,
        catalogId: 'doc',
        key: 'hysteria2|203.0.113.1:443',
      ),
      0,
    );

    // And a key that is gone from every list leaves the choice to fall back to
    // the top of the page rather than to an arbitrary row.
    expect(
      selectionAfterReload(
        catalogs: const [document, pasted],
        before: pasted,
        catalogId: 'paste',
        key: 'hysteria2|203.0.113.8:443',
      ),
      0,
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
