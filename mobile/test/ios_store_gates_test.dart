import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/core/ios_store_gates.dart';
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
    expect(windowsDialScheme('vless'), isFalse);
    expect(windowsDialScheme('hy2'), isTrue);
    expect(windowsDialScheme('trojan'), isFalse);
    expect(windowsDialScheme('ss'), isFalse);
    expect(windowsDialScheme('vmess'), isFalse);
    expect(VpnNotificationPrefs.isSupported, isFalse);
    expect(QsTilePrefs.isSupported, isFalse);
  });

  test('lib has no Platega or tariff deep link', () {
    final hits = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final normalized = entity.path.replaceAll('\\', '/');
      if (normalized.contains('/l10n/')) continue;
      final text = entity.readAsStringSync();
      if (text.contains('start=tariffs') ||
          text.contains('createPlategaPayment')) {
        hits.add(normalized);
      }
    }
    expect(hits, isEmpty);
  });
}
