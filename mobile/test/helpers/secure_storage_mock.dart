import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory mock for the flutter_secure_storage MethodChannel.
///
/// flutter_secure_storage stores everything under one channel; the Android
/// encryptedSharedPreferences options only change native behavior, not the
/// Dart call shape. Returns a reset handle so each test starts empty.
Map<String, String?> mockSecureStorage() {
  final mem = <String, String?>{};
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
    final args = call.arguments;
    final key = args is Map ? args['key'] as String? : null;
    switch (call.method) {
      case 'read':
        return key == null ? null : mem[key];
      case 'write':
        if (key != null) mem[key] = args['value'] as String?;
        return null;
      case 'delete':
        if (key != null) mem.remove(key);
        return null;
      case 'deleteAll':
        mem.clear();
        return null;
      case 'readAll':
        return Map<String, String?>.from(mem);
      default:
        return null;
    }
  });
  return mem;
}
