import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stable install id for device-slot registration (not a hardware ID).
///
/// Survives app restarts; lost on uninstall / clear secure storage → new slot.
class InstallIdStorage {
  InstallIdStorage._();
  static final InstallIdStorage instance = InstallIdStorage._();

  static const _key = 'tc.install_id';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      sharedPreferencesName: 'teremok_secure_tokens',
      preferencesKeyPrefix: 'tc_',
    ),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  /// Returns existing id or creates a new UUID v4 once.
  Future<String> getOrCreate() async {
    final existing = await _storage.read(key: _key);
    if (existing != null && existing.length >= 8) {
      return existing;
    }
    final created = _uuidV4();
    await _storage.write(key: _key, value: created);
    if (kDebugMode) {
      // ignore: avoid_print
      print('[InstallId] created');
    }
    return created;
  }

  /// Test / logout helper — does not clear JWT tokens.
  Future<void> clearForTests() => _storage.delete(key: _key);

  static String _uuidV4() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int b) => b.toRadixString(16).padLeft(2, '0');
    final h = bytes.map(hex).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-'
        '${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }
}
