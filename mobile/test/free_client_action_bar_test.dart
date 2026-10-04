import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/core/theme.dart';
import 'package:proxydom/core/widgets/app_icon.dart';
import 'package:proxydom/features/vpn/presentation/free_client_chrome.dart';
import 'package:proxydom/l10n/app_localizations.dart';

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('paste and qr stay moss and amber, with no add button', (
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
    expect(colors, [AppBrand.secondary, AppBrand.actionAmber]);
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

  testWidgets('phone refresh is an unlabeled circular-arrow beside QR', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(
      _bar(onRefresh: _noop),
    );

    expect(find.text('QR'), findsOneWidget);
    expect(find.text('Вставить'), findsOneWidget);
    expect(find.text('Обновить'), findsNothing);
    expect(find.byTooltip('Обновить'), findsOneWidget);
    expect(_refreshIcons, findsOneWidget);
    // Refresh is the sky slot; QR beside it is amber. Neither borrows the
    // notebook-margin orange that also paints the nav.
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate((widget) => widget is IconButton),
          )
          .style
          ?.backgroundColor
          ?.resolve({}),
      AppBrand.actionSky,
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('empty state shows the brand mark, not a generic folder glyph', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('ru'),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: const Scaffold(body: FreeClientEmptyState()),
      ),
    );

    final marks = tester.widgetList<Image>(
      find.byWidgetPredicate(
        (widget) => widget is Image && widget.image is AssetImage,
      ),
    );
    expect(marks, hasLength(1));
    expect(
      (marks.single.image as AssetImage).assetName,
      'assets/icon/logo_mark_nav.png',
    );
    expect(find.byIcon(AppIcons.folder), findsNothing);
    // The plate is an asset, not an Icon: it must stay out of the semantics
    // tree so a screen reader does not announce a picture above the caption.
    expect(marks.single.excludeFromSemantics, isTrue);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('windows refresh is a labeled button and has no QR', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await tester.pumpWidget(
      _bar(onRefresh: _noop),
    );

    expect(find.text('QR'), findsNothing);
    expect(find.text('Вставить'), findsOneWidget);
    expect(find.text('Обновить'), findsOneWidget);
    expect(find.byTooltip('Обновить'), findsNothing);
    final buttons = tester.widgetList<FilledButton>(
      find.byWidgetPredicate((widget) => widget is FilledButton),
    );
    expect(buttons.length, 2);
    debugDefaultTargetPlatformOverride = null;
  });
}

void _noop() {}

Widget _bar({VoidCallback? onRefresh}) {
  return MaterialApp(
    theme: AppTheme.light,
    locale: const Locale('ru'),
    localizationsDelegates: AppL10n.localizationsDelegates,
    supportedLocales: AppL10n.supportedLocales,
    home: Scaffold(
      body: FreeClientActionBar(
        onPaste: _noop,
        onScan: _noop,
        onRefresh: onRefresh,
      ),
    ),
  );
}

final _refreshIcons = find.byWidgetPredicate(
  (widget) => widget is AppIcon && widget.icon == AppIcons.refresh,
);
