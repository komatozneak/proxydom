import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/core/theme.dart';
import 'package:proxydom/features/vpn/presentation/free_client_chrome.dart';
import 'package:proxydom/l10n/app_localizations.dart';

void main() {
  testWidgets('delete is a soft clay key, and the copy says device', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('ru'),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => confirmImportedDelete(
                  context,
                  catalog: true,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Удалить этот список?'), findsOneWidget);
    expect(
      find.text('Все серверы из списка сотрутся с этого устройства.'),
      findsOneWidget,
    );

    // `TextButton.icon` builds a private TextButton subclass on some Flutter
    // releases, and `widgetWithText` matches the exact type: match any
    // TextButton above the label instead.
    final delete = tester.widget<TextButton>(
      find.ancestor(
        of: find.text('Удалить'),
        matching: find.byWidgetPredicate((widget) => widget is TextButton),
      ),
    );
    expect(
      delete.style?.foregroundColor?.resolve(<WidgetState>{}),
      AppBrand.actionClay,
    );
    expect(
      delete.style?.backgroundColor?.resolve(<WidgetState>{}),
      AppBrand.actionClay.withValues(alpha: 0.12),
    );

    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
  });
}
