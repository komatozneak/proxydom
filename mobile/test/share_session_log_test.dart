import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/features/vpn/data/share_link_parser.dart';
import 'package:proxydom/features/vpn/data/share_session_log.dart';

void main() {
  test('reality fields keep lengths and drop the key', () {
    const raw =
        'vless://11111111-1111-1111-1111-111111111111@203.0.113.10:2443'
        '?encryption=none&security=reality&sni=www.cloudflare.com&fp=chrome'
        '&pbk=EzoaRfOchWAdzsm2nNEaZeDgq7Z2PgoXzzZ-cZg13iY&sid=a1b2c3d4'
        '&type=tcp#vless-reality';
    final fields = ShareSessionLog.fieldsFor(parseShareLink(raw));
    expect(fields['security'], 'reality');
    expect(fields['fp'], 'chrome');
    expect(fields['pbk_len'], greaterThan(0));
    expect(fields['sid_len'], 8);
    expect(fields.toString().contains('EzoaRf'), isFalse);
    expect(fields.toString().contains('11111111'), isFalse);
  });

  test('hysteria obfs password is only marked set', () {
    const raw =
        'hysteria2://standHy2pass@95.182.81.27:20002?sni=stand.teremok.test'
        '&insecure=1&obfs=salamander&obfs-password=standObfsPass#hy2-obfs';
    final fields = ShareSessionLog.fieldsFor(parseShareLink(raw));
    expect(fields['obfs'], 'salamander');
    expect(fields['insecure'], isTrue);
    expect(fields['obfs_password'], 'set');
    expect(fields.toString().contains('standObfsPass'), isFalse);
    expect(fields.toString().contains('standHy2pass'), isFalse);
  });
}
