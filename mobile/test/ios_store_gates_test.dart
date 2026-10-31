import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/core/ios_store_gates.dart';
import 'package:proxydom/features/vpn/data/dial_set.dart';
import 'package:proxydom/features/settings/data/qs_tile_prefs.dart';
import 'package:proxydom/features/settings/data/vpn_notification_prefs.dart';

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('hideInAppPlategaCheckout true on iOS', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(androidPerAppSplit, isFalse);
    expect(iosAppsSplitUnsupported, isTrue);
    expect(windowsDesktop, isFalse);
    expect(sitesOnlySplit, isTrue);
  });

  test('free key client blocks cashier routes on Android', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(androidPerAppSplit, isTrue);
    expect(iosAppsSplitUnsupported, isFalse);
    expect(windowsDesktop, isFalse);
    expect(sitesOnlySplit, isFalse);
    expect(windowsDialScheme('hysteria2'), isTrue);
  });

  test('windows hides apps, shade, and the quick settings tile', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(windowsDesktop, isTrue);
    expect(androidPerAppSplit, isFalse);
    expect(sitesOnlySplit, isTrue);
    expect(iosAppsSplitUnsupported, isFalse);
    expect(windowsDialScheme('vless'), isTrue);
    expect(windowsDialScheme('hy2'), isTrue);
    // The broker now carries the whole v2ray-core family; what it still cannot
    // carry is refused by name, and that is the line this guards.
    expect(windowsDialScheme('trojan'), isTrue);
    expect(windowsDialScheme('ss'), isTrue);
    expect(windowsDialScheme('vmess'), isTrue);
    expect(windowsDialScheme('socks5'), isTrue);
    expect(windowsDialScheme('wireguard'), isFalse);
    expect(VpnNotificationPrefs.isSupported, isFalse);
    expect(QsTilePrefs.isSupported, isFalse);
  });
}
