import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:proxydom/features/settings/presentation/settings_screen.dart';
import 'package:proxydom/l10n/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('proxydom/vpn');

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('an added tile offers removal instead of a dead alert',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    var addCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'isQsTileAdded':
          return true;
        case 'isShadeNotificationEnabled':
          return true;
        case 'requestAddQsTile':
          addCalls += 1;
          return 'already_added';
        default:
          return null;
      }
    });

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

    expect(find.text('Убрать'), findsOneWidget);
    await tester.tap(find.text('Плитка в шторке'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Убрать плитку'), findsOneWidget);
    expect(
      find.text(
        'Потяните шторку вниз, нажмите карандаш и перетащите «Прокси Дом» наверх.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Плитка уже в шторке — откройте панель и пролистайте'),
      findsNothing,
    );
    expect(addCalls, 0);
    debugDefaultTargetPlatformOverride = null;
  });
}
