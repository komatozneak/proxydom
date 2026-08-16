import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One-shot recovery code archive (shown once after first register).
///
/// The recovery code is the account root (Mullvad-style), so it lives in
/// flutter_secure_storage (EncryptedSharedPreferences / Keychain) — never in
/// plaintext SharedPreferences. Legacy plaintext copies are migrated on first
/// read and deleted. [markShown] wipes the archive; [clear] wipes everything
/// on logout / identity change.
class RecoveryCodeStorage {
  RecoveryCodeStorage._();
  static final RecoveryCodeStorage instance = RecoveryCodeStorage._();

  static const _pendingKey = 'auth.recovery_code.pending';
  static const _archivedKey = 'auth.recovery_code.archived';
  static const _shownKey = 'auth.recovery_code.shown';

  final FlutterSecureStorage _secure = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      sharedPreferencesName: 'teremok_secure_recovery',
      preferencesKeyPrefix: 'tc_',
    ),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  Future<void> savePending(String code) async {
    await _secure.write(key: _pendingKey, value: code);
    await _secure.write(key: _archivedKey, value: code);
    await _secure.write(key: _shownKey, value: 'false');
    await _purgeLegacy();
  }

  Future<String?> takePending() async {
    await _migrateLegacy();
    final code = await _secure.read(key: _pendingKey);
    if (code == null || code.isEmpty) return null;
    await _secure.delete(key: _pendingKey);
    return code;
  }

  Future<String?> readArchived() async {
    await _migrateLegacy();
    return _secure.read(key: _archivedKey);
  }

  Future<bool> wasShown() async {
    await _migrateLegacy();
    return (await _secure.read(key: _shownKey)) == 'true';
  }

  Future<void> markShown() async {
    await Future.wait([
      _secure.write(key: _shownKey, value: 'true'),
      _secure.delete(key: _pendingKey),
      // Shown once — the archive must not leak the code for the install's life.
      _secure.delete(key: _archivedKey),
    ]);
  }

  /// Logout / identity change: no recovery material may survive into the
  /// next account on this install.
  Future<void> clear() async {
    await Future.wait([
      _secure.delete(key: _pendingKey),
      _secure.delete(key: _archivedKey),
      _secure.delete(key: _shownKey),
    ]);
    await _purgeLegacy();
  }

  /// Move pre-secure-storage plaintext copies over, then delete them.
  Future<void> _migrateLegacy() async {
    final prefs = await SharedPreferences.getInstance();
    final legacyPending = prefs.getString(_pendingKey);
    final legacyArchived = prefs.getString(_archivedKey);
    final legacyShown = prefs.getBool(_shownKey);
    if (legacyPending != null &&
        (await _secure.read(key: _pendingKey)) == null) {
      await _secure.write(key: _pendingKey, value: legacyPending);
    }
    if (legacyArchived != null &&
        (await _secure.read(key: _archivedKey)) == null) {
      await _secure.write(key: _archivedKey, value: legacyArchived);
    }
    if (legacyShown != null && (await _secure.read(key: _shownKey)) == null) {
      await _secure.write(key: _shownKey, value: legacyShown ? 'true' : 'false');
    }
    await _purgeLegacy();
  }

  Future<void> _purgeLegacy() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.remove(_pendingKey),
      prefs.remove(_archivedKey),
      prefs.remove(_shownKey),
    ]);
  }
}
