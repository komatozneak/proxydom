import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/core/device_platform.dart';

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('devicePlatformCode is ios on iPhone', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(devicePlatformCode(), 'ios');
  });

  test('devicePlatformCode is android on Pixel', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(devicePlatformCode(), 'android');
  });
}
