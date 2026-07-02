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

/// Хранилище JWT-токенов в Keychain (iOS) / Keystore (Android).
/// Сейчас хранит только access/refresh — больше пока ничего.
class TokenStorage implements TokenStore {
  TokenStorage._();
  static final TokenStorage instance = TokenStorage._();

  static const _accessKey = 'tc.access_token';
  static const _refreshKey = 'tc.refresh_token';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await Future.wait([
      _storage.write(key: _accessKey, value: accessToken),
      _storage.write(key: _refreshKey, value: refreshToken),
    ]);
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
