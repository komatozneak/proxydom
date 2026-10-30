import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/core/theme.dart';
import 'package:proxydom/core/widgets/app_action_button.dart';
import 'package:proxydom/features/settings/presentation/no_vpn_screen.dart';
import 'package:proxydom/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'split_tunnel_custom_sites_v1': jsonEncode([
        {
          'id': 'site-1',
          'domain': 'example.com',
          'enabled': true,
          'label': '',
          'subtitle': '',
          'players': ['player.example.com'],
        },
      ]),
    });
  });

  testWidgets('one pencil reveals explicit delete on the site row', (
    tester,
  ) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('proxydom/vpn'),
      (call) async {
        if (call.method == 'isLockdownEnabled') return false;
        return null;
      },
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        const MethodChannel('proxydom/vpn'),
        null,
      ),
    );
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tester.view
      ..physicalSize = const Size(800, 600)
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

    // Swipe-to-delete is gone; the pencil is the one way into delete mode.
    expect(find.byType(Dismissible), findsNothing);
    expect(find.byType(AppRingButton), findsOneWidget);

    await tester.tap(find.byType(AppRingButton));
    await tester.pump();

    // The pencil remains, and every row grew an explicit X.
    expect(find.byType(AppRingButton), findsNWidgets(2));
    expect(find.byTooltip('Удалить'), findsOneWidget);

    await tester.tap(find.byTooltip('Удалить'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Удалить сайт из списка?'), findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // Let the screen's native-sync retry backoff finish before teardown.
    await tester.pump(const Duration(seconds: 3));

    debugDefaultTargetPlatformOverride = null;
  });
}
