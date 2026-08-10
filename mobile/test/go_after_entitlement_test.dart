import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teremok_connect/core/router.dart';
import 'package:teremok_connect/features/auth/data/recovery_code_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppRouter.pendingRecoveryCode = null;
    AppRouter.postAuthResolved = false;
  });

  test('pendingRecoveryCode forces /recovery destination decision', () async {
    AppRouter.pendingRecoveryCode = 'ABCD-EFGH';
    final shown = await RecoveryCodeStorage.instance.wasShown();
    expect(shown, isFalse);
    expect(AppRouter.pendingRecoveryCode, 'ABCD-EFGH');
  });

  test('markShown clears pending storage flag', () async {
    await RecoveryCodeStorage.instance.savePending('CODE-1234');
    expect(await RecoveryCodeStorage.instance.wasShown(), isFalse);
    await RecoveryCodeStorage.instance.markShown();
    expect(await RecoveryCodeStorage.instance.wasShown(), isTrue);
    expect(await RecoveryCodeStorage.instance.takePending(), isNull);
  });
}
