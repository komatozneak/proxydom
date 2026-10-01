import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/core/theme.dart';
import 'package:teremok_connect/features/vpn/presentation/free_client_chrome.dart';
import 'package:teremok_connect/l10n/app_localizations.dart';

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('paste and qr stay moss and margin, with no add button', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
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
    expect(find.text('QR'), findsOneWidget);
    final buttons = tester.widgetList<FilledButton>(
      find.byWidgetPredicate((widget) => widget is FilledButton),
    );
    final colors = buttons
        .map((button) => button.style?.backgroundColor?.resolve({}))
        .toList();
    expect(colors, [AppBrand.secondary, AppBrand.paperMargin]);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('windows keeps paste and drops the QR button', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('ru'),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: Scaffold(
          body: Column(
            children: [
              FreeClientActionBar(onPaste: _noop, onScan: _noop),
              const FreeClientEmptyState(),
            ],
          ),
        ),
      ),
    );

    expect(find.text('QR'), findsNothing);
    expect(find.text('Вставить'), findsOneWidget);
    expect(find.text('Добавьте ссылку, ключ или QR-код.'), findsNothing);
    expect(find.text('Вставьте ссылку или ключ.'), findsOneWidget);
    final buttons = tester.widgetList<FilledButton>(
      find.byWidgetPredicate((widget) => widget is FilledButton),
    );
    expect(buttons.length, 1);
    debugDefaultTargetPlatformOverride = null;
  });
}

void _noop() {}
