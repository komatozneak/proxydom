import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/core/ios_store_gates.dart';

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('hideInAppPlategaCheckout true on iOS', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(freeKeyClient, isTrue);
    expect(hideInAppPlategaCheckout, isTrue);
    expect(iosAppsSplitUnsupported, isTrue);
    expect(referralLandingPath, '/home');
    expect(iosFreeClientRouteBlocked('/subscription'), isTrue);
    expect(iosFreeClientRouteBlocked('/settings/devices'), isTrue);
    expect(iosFreeClientRouteBlocked('/import'), isFalse);
  });

  test('free key client blocks cashier routes on Android', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(freeKeyClient, isTrue);
    expect(hideInAppPlategaCheckout, isTrue);
    expect(iosAppsSplitUnsupported, isFalse);
    expect(referralLandingPath, '/home');
    expect(iosFreeClientRouteBlocked('/subscription'), isTrue);
    expect(iosFreeClientRouteBlocked('/premium'), isTrue);
    expect(iosFreeClientRouteBlocked('/settings/account'), isTrue);
    expect(iosFreeClientRouteBlocked('/import'), isFalse);
  });
}
