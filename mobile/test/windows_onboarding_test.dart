import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/core/theme.dart';
import 'package:proxydom/features/onboarding/presentation/onboarding_screen.dart';
import 'package:proxydom/features/vpn/data/vpn_disclosure_prefs.dart';
import 'package:proxydom/features/vpn/presentation/vpn_disclosure_dialog.dart';
import 'package:proxydom/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app(Widget home) {
  return ProviderScope(
    child: MaterialApp(
      theme: AppTheme.light,
      locale: const Locale('ru'),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      home: home,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Windows onboarding is one compact panel, not a card carousel',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await tester.pumpWidget(_app(const OnboardingScreen()));
      await tester.pumpAndSettle();

      expect(find.byType(PageView), findsNothing);
      expect(find.text('Подключение на компьютере'), findsOneWidget);
      expect(find.text('Добавить сервер'), findsOneWidget);
      expect(find.textContaining('домик', findRichText: true), findsNothing);
      expect(find.textContaining('дверь', findRichText: true), findsNothing);
      expect(find.textContaining('Android', findRichText: true), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Windows connect does not show the Android VPN disclosure',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      var allowed = false;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  allowed = await VpnDisclosureDialog.ensureAccepted(context);
                },
                child: const Text('connect'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('connect'));
      await tester.pumpAndSettle();

      expect(allowed, isTrue);
      expect(find.text('Как включается туннель'), findsNothing);
      expect(await VpnDisclosurePrefs.isAccepted(), isFalse);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
