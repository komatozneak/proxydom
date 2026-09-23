import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/core/theme.dart';
import 'package:teremok_connect/features/vpn/presentation/free_client_chrome.dart';
import 'package:teremok_connect/l10n/app_localizations.dart';

void main() {
  testWidgets('add paste and qr keep oak moss and margin colors', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('ru'),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: Scaffold(
          body: FreeClientActionBar(
            onAdd: () {},
            onPaste: () {},
            onScan: () {},
          ),
        ),
      ),
    );

    final buttons = tester.widgetList<FilledButton>(find.byType(FilledButton));
    final colors = buttons
        .map((button) => button.style?.backgroundColor?.resolve({}))
        .toList();
    expect(colors, [
      AppBrand.primary,
      AppBrand.secondary,
      AppBrand.paperMargin,
    ]);
  });

  testWidgets('add screen keeps equal paste and qr buttons', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('ru'),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: Scaffold(
          body: FreeClientActionBar(
            showAdd: false,
            onPaste: () {},
            onScan: () {},
          ),
        ),
      ),
    );

    expect(find.text('Добавить'), findsNothing);
    final buttons = tester.widgetList<FilledButton>(find.byType(FilledButton));
    final colors = buttons
        .map((button) => button.style?.backgroundColor?.resolve({}))
        .toList();
    expect(colors, [AppBrand.secondary, AppBrand.paperMargin]);
  });
}
