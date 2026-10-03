import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';

import 'package:proxydom/core/device_label.dart';

void main() {
  test('Pixel uses model, not Google manufacturer', () {
    expect(
      formatOsDeviceLabel(
        settingsName: '',
        brand: 'google',
        manufacturer: 'Google',
        model: 'Pixel 8',
      ),
      'Pixel 8',
    );
  });

  test('prefers Settings device name over model code', () {
    expect(
      formatOsDeviceLabel(
        settingsName: 'Galaxy S24',
        brand: 'samsung',
        manufacturer: 'samsung',
        model: 'SM-S921B',
      ),
      'Galaxy S24',
    );
  });

  test('prefixes manufacturer when model is a SKU', () {
    expect(
      formatOsDeviceLabel(
        settingsName: '',
        brand: 'xiaomi',
        manufacturer: 'Xiaomi',
        model: '2304FPN6DC',
      ),
      'Xiaomi 2304FPN6DC',
    );
  });

  test('ignores generic settings name', () {
    expect(
      formatOsDeviceLabel(
        settingsName: 'Android',
        brand: 'google',
        manufacturer: 'Google',
        model: 'Pixel 8 Pro',
      ),
      'Pixel 8 Pro',
    );
  });

  test('readOsDeviceLabel maps native payload', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('proxydom/vpn');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getDeviceLabel') {
        return {
          'settingsName': '',
          'brand': 'google',
          'manufacturer': 'Google',
          'model': 'Pixel 8',
        };
      }
      return null;
    });
    expect(await readOsDeviceLabel(channel: channel), 'Pixel 8');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
}
