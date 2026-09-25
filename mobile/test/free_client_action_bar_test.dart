import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/core/theme.dart';
import 'package:teremok_connect/features/vpn/presentation/free_client_chrome.dart';
import 'package:teremok_connect/l10n/app_localizations.dart';

void main() {
  testWidgets('paste and qr stay moss and margin, with no add button', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('ru'),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: Scaffold(
          body: FreeClientActionBar(
            onPaste: () {},
            onScan: () {},
          ),
        ),
      ),
    );

    expect(find.text('Добавить'), findsNothing);
    final buttons = tester.widgetList<FilledButton>(
      find.byWidgetPredicate((widget) => widget is FilledButton),
    );
    final colors = buttons
        .map((button) => button.style?.backgroundColor?.resolve({}))
        .toList();
    expect(colors, [AppBrand.secondary, AppBrand.paperMargin]);
  });
}
