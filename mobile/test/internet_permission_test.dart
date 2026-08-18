import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/core/internet_permission.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('teremok/vpn');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('non-Android skips the native prompt', () async {
    expect(
      await ensureInternetPermissionGranted(channel: channel, isAndroid: false),
      isTrue,
    );
  });

  test('Android waits for native grant', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'ensureInternetPermission');
      return true;
    });
    expect(
      await ensureInternetPermissionGranted(channel: channel, isAndroid: true),
      isTrue,
    );
  });

  test('Android denied grant is false', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => false);
    expect(
      await ensureInternetPermissionGranted(channel: channel, isAndroid: true),
      isFalse,
    );
  });

  test('missing method on Android does not block bootstrap', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
    expect(
      await ensureInternetPermissionGranted(channel: channel, isAndroid: true),
      isTrue,
    );
  });

  test('bindToUnderlyingNetwork is invoked on Android', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'bindToUnderlyingNetwork');
      return true;
    });
    expect(
      await bindProcessToUnderlyingNetwork(channel: channel, isAndroid: true),
      isTrue,
    );
  });
}
