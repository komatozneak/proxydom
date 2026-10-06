import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/core/legal/third_party_notices.dart';
import 'package:proxydom/features/settings/presentation/settings_screen.dart';
import 'package:proxydom/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('about row opens the license page with the engine notices',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          locale: Locale('ru'),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          home: SettingsScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    registerThirdPartyNotices();

    await tester.tap(find.text('О приложении'));
    // The license list loads behind a progress indicator, which never goes
    // idle, so pumpAndSettle does not return. The asset read now happens
    // inside that load, on a real future, so fake-async pumps alone never
    // finish it.
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await _until(tester, find.text('hy2bind'));

    await tester.tap(find.text('hy2bind'));
    await _until(tester, find.textContaining('apernet/hysteria'));
    expect(find.textContaining('xjasonlyu/tun2socks'), findsWidgets);
    expect(find.textContaining('refraction-networking/utls'), findsWidgets);
  });

  testWidgets('the notices asset is unread until licenses are listed',
      (tester) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    var reads = 0;
    messenger.setMockMessageHandler('flutter/assets', (ByteData? message) {
      if (message != null && _isNoticesRequest(message)) reads += 1;
      // delegate.send is the loader the test uses when no mock is installed.
      // Counting here and forwarding keeps every other asset working.
      return messenger.delegate.send('flutter/assets', message);
    });
    addTearDown(() => messenger.setMockMessageHandler('flutter/assets', null));
    // A previous test may have cached the file. The cache would hide the
    // channel request this test exists to count.
    rootBundle.evict(thirdPartyNoticesAsset);

    registerThirdPartyNotices();
    expect(reads, 0);
    // ignore: avoid_print
    print('notices asset reads after registerThirdPartyNotices: $reads');

    await tester.runAsync(() => LicenseRegistry.licenses.drain<void>());
    expect(reads, greaterThan(0));
    // ignore: avoid_print
    print('notices asset reads after LicenseRegistry.licenses: $reads');
  });
}

bool _isNoticesRequest(ByteData message) {
  final bytes = message.buffer.asUint8List(
    message.offsetInBytes,
    message.lengthInBytes,
  );
  return utf8.decode(bytes).contains('THIRD-PARTY-NOTICES.md');
}

Future<void> _until(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
  expect(finder, findsWidgets);
}
