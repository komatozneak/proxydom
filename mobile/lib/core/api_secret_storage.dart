import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Per-device HMAC API secret (ADR 009). Returned once at register/recover.
class ApiSecretStorage {
  ApiSecretStorage._();
  static final ApiSecretStorage instance = ApiSecretStorage._();

  static const _key = 'tc.api_secret';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      sharedPreferencesName: 'teremok_secure_tokens',
      preferencesKeyPrefix: 'tc_',
    ),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  Future<void> save(String secret) async {
    final trimmed = secret.trim();
    if (trimmed.isEmpty) return;
    await _storage.write(key: _key, value: trimmed);
  }

  Future<String?> read() => _storage.read(key: _key);

  Future<void> clear() => _storage.delete(key: _key);
}
