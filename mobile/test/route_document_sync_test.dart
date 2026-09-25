import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/features/vpn/data/route_document.dart';

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

  test('iOS dials only hysteria2', () {
    expect(canDialScheme('hysteria2', ios: true), isTrue);
    expect(canDialScheme('hy2', ios: true), isTrue);
    expect(canDialScheme('vless', ios: true), isFalse);
    expect(canDialScheme('vless', ios: false), isTrue);
    expect(canDialScheme('ss', ios: false), isTrue);
  });

  test('update interval is a positive hour count', () {
    expect(parseUpdateIntervalHours('12'), 12);
    expect(parseUpdateIntervalHours('0'), isNull);
    expect(parseUpdateIntervalHours('nope'), isNull);
  });
}
