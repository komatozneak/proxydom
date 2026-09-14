import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/features/referral/data/referral_code_format.dart';

void main() {
  test('referral deep link round-trip is not seat join', () {
    final uri = referralDeepLink('tg-buy-it');
    expect(uri.scheme, 'teremokconnect');
    expect(uri.host, 'ref');
    expect(referralCodeFromUri(uri), 'TG-BUY-IT');
    expect(
      referralCodeFromUri(Uri.parse('teremokconnect://join?code=ABC123')),
      isNull,
    );
  });
}
