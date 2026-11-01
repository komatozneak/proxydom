import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/core/theme.dart';
import 'package:proxydom/features/settings/presentation/no_vpn_screen.dart';
import 'package:proxydom/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, Object> _site(String id, String domain, List<String> players) => {
      'id': id,
      'domain': domain,
      'enabled': true,
      'label': '',
      'subtitle': '',
      'players': players,
    };

/// Under every saved site the list says how many players came with it, zero
/// included, so "none found" is not mistaken for "never checked".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('every site shows its player count, in Russian plurals', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'split_tunnel_custom_sites_v1': jsonEncode([
        _site('a', 'one.example', ['p1.example']),
        _site('b', 'three.example', ['p1.example', 'p2.example', 'p3.example']),
        _site('c', 'five.example',
            ['a.example', 'b.example', 'c.example', 'd.example', 'e.example']),
      ]),
      // Players already known for every enabled site: the screen must not try
      // to fetch pages in a test.
    });
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('proxydom/vpn'),
      (call) async => call.method == 'isLockdownEnabled' ? false : null,
    );
    addTearDown(() => messenger.setMockMethodCallHandler(
        const MethodChannel('proxydom/vpn'), null));
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tester.view
      ..physicalSize = const Size(800, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          locale: const Locale('ru'),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          home: const NoVpnScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.text('(обнаружен 1 плеер)'), findsOneWidget);
    expect(find.text('(обнаружено 3 плеера)'), findsOneWidget);
    expect(find.text('(обнаружено 5 плееров)'), findsOneWidget);
    // Let the screen's native-sync retry backoff finish before teardown.
    await tester.pump(const Duration(seconds: 3));
    debugDefaultTargetPlatformOverride = null;
  });

  test('the zero case says so, in both languages', () async {
    final ru = await AppL10n.delegate.load(const Locale('ru'));
    final en = await AppL10n.delegate.load(const Locale('en'));
    expect(ru.splitTunnelPlayersDetected(0), '(плееры не обнаружены)');
    expect(en.splitTunnelPlayersDetected(0), '(no players detected)');
    expect(en.splitTunnelPlayersDetected(2), '(2 players detected)');
  });
}
