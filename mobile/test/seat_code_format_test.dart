import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/features/auth/data/seat_code_format.dart';

void main() {
  test('formatSeatCodeDisplay groups six chars', () {
    expect(formatSeatCodeDisplay('abc123'), 'ABC-123');
    expect(normalizeSeatCode('ab-c1 23'), 'ABC123');
  });

  test('seatJoinDeepLink and parse round-trip', () {
    final uri = seatJoinDeepLink('abc123');
    expect(uri.scheme, 'teremokconnect');
    expect(uri.host, 'join');
    expect(seatCodeFromJoinUri(uri), 'ABC123');
    expect(
      seatCodeFromJoinUri(Uri.parse('https://example.com')),
      isNull,
    );
  });
}
