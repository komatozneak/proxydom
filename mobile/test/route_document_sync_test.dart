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

  test('import dial follows the link, not the scheme name', () {
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
    // Reality has its own engine, so the vless scheme is enough for a lone
    // paste and for a document made only of those lines.
    expect(
      shareImportDial([reality], fromDocument: false),
      ShareImportDial.dialable,
    );
    expect(
      shareImportDial([reality], fromDocument: true),
      ShareImportDial.dialable,
    );
    expect(
      shareImportDial([trojan], fromDocument: false),
      ShareImportDial.dialable,
    );
    expect(
      shareImportDial([trojan], fromDocument: true),
      ShareImportDial.dialable,
    );
    expect(
      shareImportDial([hy2, trojan], fromDocument: true),
      ShareImportDial.dialable,
    );

    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    // iOS carries the v2ray family on the packet-flow dataplane now.
    expect(
      shareImportDial([vless], fromDocument: false),
      ShareImportDial.dialable,
    );
    expect(
      shareImportDial([vless], fromDocument: true),
      ShareImportDial.dialable,
    );
    expect(
      shareImportDial([hy2], fromDocument: false),
      ShareImportDial.dialable,
    );

    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    // Windows carries VLESS on the same core as Android now.
    expect(
      shareImportDial([vless], fromDocument: false),
      ShareImportDial.dialable,
    );
    expect(
      shareImportDial([vless], fromDocument: true),
      ShareImportDial.dialable,
    );
    expect(
      shareImportDial([hy2, vless], fromDocument: true),
      ShareImportDial.dialable,
    );
    // The REALITY engine is the same on Windows as on Android.
    expect(
      shareImportDial([reality], fromDocument: false),
      ShareImportDial.dialable,
    );
    expect(
      shareImportDial([reality], fromDocument: true),
      ShareImportDial.dialable,
    );
    // The gate is still per link, not per scheme: a vless line over XHTTP has
    // no engine, so it stays out although its scheme is admitted.
    final xhttp = parseShareLink(
      'vless://11111111-1111-1111-1111-111111111111@203.0.113.10:443'
      '?security=tls&type=xhttp&path=%2Fx#X',
    );
    expect(
      shareImportDial([xhttp], fromDocument: false),
      ShareImportDial.singleUnsupported,
    );
    expect(
      shareImportDial([xhttp], fromDocument: true),
      ShareImportDial.noneDialable,
    );
  });

  test('update interval is a positive hour count', () {
    expect(parseUpdateIntervalHours('12'), 12);
    expect(parseUpdateIntervalHours('0'), isNull);
    expect(parseUpdateIntervalHours('nope'), isNull);
  });
}
