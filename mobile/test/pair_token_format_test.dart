import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/features/auth/data/pair_token_format.dart';

void main() {
  test('pair deep link round-trip is not seat or referral', () {
    final uri = pairDeepLink('aabbccddeeff00112233445566778899');
    expect(uri.scheme, 'teremokconnect');
    expect(uri.host, 'pair');
    expect(
      pairTokenFromUri(uri),
      'aabbccddeeff00112233445566778899',
    );
    expect(
      pairTokenFromUri(Uri.parse('teremokconnect://join?code=ABC123')),
      isNull,
    );
    expect(
      pairTokenFromUri(Uri.parse('teremokconnect://ref?code=TG-BUY')),
      isNull,
    );
  });

  test('normalizePairTokenInput accepts uri or bare hex', () {
    expect(
      normalizePairTokenInput(
        'teremokconnect://pair?token=aabbccddeeff00112233445566778899',
      ),
      'aabbccddeeff00112233445566778899',
    );
    expect(
      normalizePairTokenInput('AABBCCDDEEFF00112233445566778899'),
      'aabbccddeeff00112233445566778899',
    );
    expect(normalizePairTokenInput('TRM-ABCD-EFGH-IJKL'), isNull);
  });
}
