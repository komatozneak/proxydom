import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:proxydom/core/theme.dart';
import 'package:proxydom/features/vpn/data/vpn_disclosure_prefs.dart';
import 'package:proxydom/features/vpn/presentation/vpn_disclosure_dialog.dart';
import 'package:proxydom/l10n/app_localizations.dart';

int _connects = 0;

Widget _nestHarness() {
  return MaterialApp(
    theme: AppTheme.light,
    locale: const Locale('ru'),
    localizationsDelegates: AppL10n.localizationsDelegates,
    supportedLocales: AppL10n.supportedLocales,
    home: Builder(
      builder: (context) {
        return Scaffold(
          body: TextButton(
            onPressed: () async {
              final allowed = await VpnDisclosureDialog.ensureAccepted(context);
              if (allowed) _connects++;
            },
            child: const Text('nest'),
          ),
        );
      },
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _connects = 0;
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('first Nest tap shows disclosure; decline does not connect',
      (tester) async {
    await tester.pumpWidget(_nestHarness());
    await tester.tap(find.text('nest'));
    await tester.pumpAndSettle();

    expect(find.text('Как включается туннель'), findsOneWidget);
    expect(_connects, 0);

    await tester.tap(find.text('Не сейчас'));
    await tester.pumpAndSettle();

    expect(find.text('Как включается туннель'), findsNothing);
    expect(_connects, 0);
    expect(await VpnDisclosurePrefs.isAccepted(), isFalse);
  });

  testWidgets('decline then Nest shows disclosure again', (tester) async {
    await tester.pumpWidget(_nestHarness());
    await tester.tap(find.text('nest'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Не сейчас'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('nest'));
    await tester.pumpAndSettle();
    expect(find.text('Как включается туннель'), findsOneWidget);
    expect(_connects, 0);
  });

  testWidgets('accept connects; second Nest skips disclosure', (tester) async {
    await tester.pumpWidget(_nestHarness());
    await tester.tap(find.text('nest'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Принимаю и продолжить'));
    await tester.pumpAndSettle();

    expect(find.text('Как включается туннель'), findsNothing);
    expect(_connects, 1);
    expect(await VpnDisclosurePrefs.isAccepted(), isTrue);

    await tester.tap(find.text('nest'));
    await tester.pumpAndSettle();

    expect(find.text('Как включается туннель'), findsNothing);
    expect(_connects, 2);
  });
}
