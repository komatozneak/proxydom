import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/features/vpn/data/route_document.dart';
import 'package:teremok_connect/features/vpn/data/share_link_parser.dart';

void main() {
  test('200 with a share line replaces the document', () {
    expect(
      decideDocumentSync(
        status: 200,
        body: 'hysteria2://user:pass@203.0.113.10:443/?sni=a.example#US',
      ),
      DocumentSyncDecision.replace,
    );
  });

  test('304 leaves the saved lines', () {
    expect(
      decideDocumentSync(status: 304),
      DocumentSyncDecision.unchanged,
    );
  });

  test('404 and 410 drop the document', () {
    expect(decideDocumentSync(status: 404), DocumentSyncDecision.drop);
    expect(decideDocumentSync(status: 410), DocumentSyncDecision.drop);
  });

  test('an empty 200 drops the document', () {
    expect(
      decideDocumentSync(status: 200, body: '   '),
      DocumentSyncDecision.drop,
    );
    expect(
      decideDocumentSync(status: 200, body: 'hello'),
      DocumentSyncDecision.drop,
    );
  });

  test('a broken share line keeps the saved document', () {
    expect(
      decideDocumentSync(status: 200, body: 'vless://'),
      DocumentSyncDecision.keep,
    );
  });

  test('transport failure and 5xx keep the saved document', () {
    expect(
      decideDocumentSync(status: 200, transportFailed: true),
      DocumentSyncDecision.keep,
    );
    expect(decideDocumentSync(status: 503), DocumentSyncDecision.keep);
  });

  test('dial gate admits only hysteria2 on every platform', () {
    for (final ios in [true, false]) {
      expect(canDialScheme('hysteria2', ios: ios), isTrue);
      expect(canDialScheme('hy2', ios: ios), isTrue);
      expect(canDialScheme('vless', ios: ios), isFalse);
      expect(canDialScheme('vmess', ios: ios), isFalse);
      expect(canDialScheme('trojan', ios: ios), isFalse);
      expect(canDialScheme('ss', ios: ios), isFalse);
    }
  });

  test('a single vless paste is rejected; a mixed document is kept', () {
    final vless = parseShareLink(
      'vless://11111111-1111-1111-1111-111111111111@203.0.113.10:443#A',
    );
    final hy2 = parseShareLink(
      'hysteria2://user:pass@203.0.113.10:443/?sni=a.example#US',
    );
    expect(
      shareImportDial([vless], fromDocument: false),
      ShareImportDial.singleUnsupported,
    );
    expect(
      shareImportDial([hy2, vless], fromDocument: false),
      ShareImportDial.hasHy2,
    );
    expect(
      shareImportDial([vless], fromDocument: true),
      ShareImportDial.noneHy2,
    );
  });

  test('update interval is a positive hour count', () {
    expect(parseUpdateIntervalHours('12'), 12);
    expect(parseUpdateIntervalHours('0'), isNull);
    expect(parseUpdateIntervalHours('nope'), isNull);
  });
}
