import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teremok_connect/features/auth/data/recovery_code_storage.dart';

import 'helpers/secure_storage_mock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockSecureStorage();
  });

  test('savePending stores code in secure storage and purges legacy prefs',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth.recovery_code.pending', 'LEGACY-PENDING');

    await RecoveryCodeStorage.instance.savePending('TRM-NEW-CODE');

    expect(await RecoveryCodeStorage.instance.takePending(), 'TRM-NEW-CODE');
    // Legacy plaintext copies must not survive.
    expect(prefs.getString('auth.recovery_code.pending'), isNull);
    expect(prefs.getString('auth.recovery_code.archived'), isNull);
  });

  test('markShown wipes the archive — code does not outlive the one-shot UI',
      () async {
    await RecoveryCodeStorage.instance.savePending('TRM-ARCHIVE-ME');
    expect(await RecoveryCodeStorage.instance.readArchived(), 'TRM-ARCHIVE-ME');

    await RecoveryCodeStorage.instance.markShown();

    expect(await RecoveryCodeStorage.instance.wasShown(), isTrue);
    expect(await RecoveryCodeStorage.instance.readArchived(), isNull);
    expect(await RecoveryCodeStorage.instance.takePending(), isNull);
  });

  test('clear wipes pending, archived and shown flag (logout)', () async {
    await RecoveryCodeStorage.instance.savePending('TRM-LOGOUT');

    await RecoveryCodeStorage.instance.clear();

    expect(await RecoveryCodeStorage.instance.takePending(), isNull);
    expect(await RecoveryCodeStorage.instance.readArchived(), isNull);
    expect(await RecoveryCodeStorage.instance.wasShown(), isFalse);
  });

  test('legacy plaintext archive migrates into secure storage on read',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth.recovery_code.archived', 'TRM-LEGACY');
    await prefs.setBool('auth.recovery_code.shown', false);

    expect(await RecoveryCodeStorage.instance.readArchived(), 'TRM-LEGACY');
    // Migrated out of plaintext.
    expect(prefs.getString('auth.recovery_code.archived'), isNull);
    // Second read comes from secure storage.
    expect(await RecoveryCodeStorage.instance.readArchived(), 'TRM-LEGACY');
  });
}
