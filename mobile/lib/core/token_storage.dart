import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Контракт хранилища JWT — для подмены в unit-тестах interceptor'а.
abstract class TokenStore {
  Future<String?> readAccessToken();
  Future<String?> readRefreshToken();
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  });
  Future<void> clear();
}

/// Хранилище JWT-токенов в Keychain (iOS) / EncryptedSharedPreferences (Android).
///
/// Android: named prefs + prefix so Auto Backup / debug reinstalls are less
/// likely to wipe or collide with other encrypted stores.
class TokenStorage implements TokenStore {
  TokenStorage._();
  static final TokenStorage instance = TokenStorage._();

  static const _accessKey = 'tc.access_token';
  static const _refreshKey = 'tc.refresh_token';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      sharedPreferencesName: 'teremok_secure_tokens',
      preferencesKeyPrefix: 'tc_',
    ),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    // Trim — whitespace/newlines in Bearer break HTTP and can yield Caddy 400.
    final access = accessToken.trim();
    final refresh = refreshToken.trim();
    await Future.wait([
      _storage.write(key: _accessKey, value: access),
      _storage.write(key: _refreshKey, value: refresh),
    ]);
    if (kDebugMode) {
      final check = await readRefreshToken();
      // ignore: avoid_print
      print(
        '[TokenStorage] saved refresh=${check != null && check.isNotEmpty}',
      );
    }
  }

  @override
  Future<String?> readAccessToken() => _storage.read(key: _accessKey);

  @override
  Future<String?> readRefreshToken() => _storage.read(key: _refreshKey);

  @override
  Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: _accessKey),
      _storage.delete(key: _refreshKey),
    ]);
  }
}
