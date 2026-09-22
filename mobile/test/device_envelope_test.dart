import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:teremok_connect/core/device_info_helper.dart';
import 'package:teremok_connect/features/vpn/data/device_envelope.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'read') return 'mock-install-uuid-1234';
      if (call.method == 'write') return null;
      return null;
    });
  });

  test('DeviceEnvelope query includes device_id and optional fields', () {
    const env = DeviceEnvelope(
      deviceId: 'abcd-1234-efgh-5678',
      deviceName: 'Pixel',
      platform: 'android',
    );
    final q = env.toQueryParameters();
    expect(q['device_id'], 'abcd-1234-efgh-5678');
    expect(q['device_name'], 'Pixel');
    expect(q['platform'], 'android');
  });

  test('DeviceEnvelope omits empty optional fields', () {
    const env = DeviceEnvelope(deviceId: 'abcd-1234-efgh-5678');
    final q = env.toQueryParameters();
    expect(q.keys, ['device_id']);
  });

  test('buildDeviceEnvelope populates device_name from platform/model', () async {
    final env = await buildDeviceEnvelope();
    expect(env.deviceId, isNotEmpty);
    expect(env.deviceName, isNotNull);
    expect(env.deviceName, isNotEmpty);
  });

  test('buildDeviceEnvelope sends ios when target platform is iOS', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final env = await buildDeviceEnvelope();
    expect(env.platform, 'ios');
  });

  test('DeviceInfoHelper returns fallback name when platform channel missing', () async {
    final name = await DeviceInfoHelper.getDeviceModelName();
    expect(name, isNotEmpty);
  });
}
