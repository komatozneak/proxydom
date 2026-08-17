import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/core/theme.dart';
import 'package:teremok_connect/features/settings/presentation/rename_device_dialog.dart';
import 'package:teremok_connect/l10n/app_localizations.dart';

Widget _app(Widget home) {
  return MaterialApp(
    theme: AppTheme.light,
    locale: const Locale('ru'),
    localizationsDelegates: AppL10n.localizationsDelegates,
    supportedLocales: AppL10n.supportedLocales,
    home: home,
  );
}

void main() {
  testWidgets(
    'RenameDeviceDialog submit returns trimmed name without framework assert',
    (tester) async {
      String? result;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showDialog<String>(
                    context: context,
                    useRootNavigator: true,
                    builder: (_) =>
                        const RenameDeviceDialog(initial: 'Android'),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), ' Pixel 7 ');
      await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      expect(result, 'Pixel 7');
    },
  );

  testWidgets(
    'RenameDeviceDialog cancel returns null without framework assert',
    (tester) async {
      var completed = false;
      String? result = 'sentinel';
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showDialog<String>(
                    context: context,
                    useRootNavigator: true,
                    builder: (_) =>
                        const RenameDeviceDialog(initial: 'Android'),
                  );
                  completed = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Pixel');
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      expect(completed, isTrue);
      expect(result, isNull);
    },
  );
}
