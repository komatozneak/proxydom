import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/core/ios_store_gates.dart';

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('hideInAppPlategaCheckout true on iOS', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(hideInAppPlategaCheckout, isTrue);
    expect(iosAppsSplitUnsupported, isTrue);
  });

  test('hideInAppPlategaCheckout false on Android', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(hideInAppPlategaCheckout, isFalse);
    expect(iosAppsSplitUnsupported, isFalse);
  });
}
