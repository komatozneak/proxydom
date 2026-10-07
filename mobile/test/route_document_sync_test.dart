import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/features/vpn/data/route_document.dart';
import 'package:proxydom/features/vpn/data/share_link_parser.dart';

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

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

  test('import dial follows the link, not the scheme name (ADR 035)', () {
    final vless = parseShareLink(
      'vless://11111111-1111-1111-1111-111111111111@203.0.113.10:443'
      '?security=tls&type=ws&path=%2Fws#A',
    );
    final reality = parseShareLink(
      'vless://11111111-1111-1111-1111-111111111111@203.0.113.10:443'
      '?security=reality&sni=www.example.com&pbk=PUBLIC&sid=ab#R',
    );
    final trojan = parseShareLink('trojan://secret@203.0.113.10:443#A');
    final hy2 = parseShareLink(
      'hysteria2://user:pass@203.0.113.10:443/?sni=a.example#US',
    );

    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(
      shareImportDial([vless], fromDocument: false),
      ShareImportDial.dialable,
    );
    expect(
      shareImportDial([hy2, vless], fromDocument: false),
      ShareImportDial.dialable,
    );
    expect(
      shareImportDial([vless], fromDocument: true),
      ShareImportDial.dialable,
    );
    // Reality is the vless scheme and still cannot start: the engine cannot
    // describe it, so a lone paste is refused and a document of only those
    // lines is kept.
    expect(
      shareImportDial([reality], fromDocument: false),
      ShareImportDial.singleUnsupported,
    );
    expect(
      shareImportDial([reality], fromDocument: true),
      ShareImportDial.noneDialable,
    );
    expect(
      shareImportDial([trojan], fromDocument: false),
      ShareImportDial.singleUnsupported,
    );
    expect(
      shareImportDial([trojan], fromDocument: true),
      ShareImportDial.noneDialable,
    );
    expect(
      shareImportDial([hy2, trojan], fromDocument: true),
      ShareImportDial.dialable,
    );

    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(
      shareImportDial([vless], fromDocument: false),
      ShareImportDial.singleUnsupported,
    );
    expect(
      shareImportDial([vless], fromDocument: true),
      ShareImportDial.noneDialable,
    );
    expect(
      shareImportDial([hy2], fromDocument: false),
      ShareImportDial.dialable,
    );

    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(
      shareImportDial([vless], fromDocument: true),
      ShareImportDial.noneDialable,
    );
    expect(
      shareImportDial([hy2, vless], fromDocument: true),
      ShareImportDial.dialable,
    );
  });

  test('update interval is a positive hour count', () {
    expect(parseUpdateIntervalHours('12'), 12);
    expect(parseUpdateIntervalHours('0'), isNull);
    expect(parseUpdateIntervalHours('nope'), isNull);
  });
}
