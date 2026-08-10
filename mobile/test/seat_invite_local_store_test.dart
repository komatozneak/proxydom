import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teremok_connect/features/auth/data/seat_invite_local_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('normalize strips and uppercases like backend', () {
    expect(SeatInviteLocalStore.normalize(' ab-12cd '), 'AB12CD');
  });

  test('wasMintedHere is true after rememberMinted', () async {
    final store = SeatInviteLocalStore.instance;
    expect(await store.wasMintedHere('ABC123'), isFalse);
    await store.rememberMinted('abc123');
    expect(await store.wasMintedHere('ABC123'), isTrue);
    expect(await store.wasMintedHere('abc-123'), isTrue);
  });
}
