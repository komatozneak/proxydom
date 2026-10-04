import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/core/theme.dart';
import 'package:proxydom/core/widgets/app_action_button.dart';
import 'package:proxydom/core/widgets/app_icon.dart';
import 'package:proxydom/features/vpn/presentation/free_client_chrome.dart';
import 'package:proxydom/l10n/app_localizations.dart';

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('refresh and paste keep the house colours, QR is a ring', (
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
    expect(find.byTooltip('QR'), findsOneWidget);
    final colors = tester
        .widgetList<AppActionButton>(
          find.byWidgetPredicate((widget) => widget is AppActionButton),
        )
        .map((button) => button.color)
        .toList();
    // Refresh first, paste last — the familiar order under the house.
    expect(colors, [AppBrand.mascotGoldDeep, AppBrand.mascotGold]);
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
    final buttons = tester.widgetList<AppActionButton>(
      find.byWidgetPredicate((widget) => widget is AppActionButton),
    );
    expect(buttons.length, 1);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('phone QR is an unlabeled ring and refresh is a full key', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(
      _bar(onRefresh: _noop),
    );

    expect(find.text('QR'), findsNothing);
    expect(find.text('Вставить'), findsOneWidget);
    expect(find.text('Обновить'), findsOneWidget);
    expect(find.byTooltip('QR'), findsOneWidget);
    expect(_qrIcons, findsOneWidget);
    // QR wears the same gold as the paste key, as a ring: it is the quiet
    // third action and must not outshout the house itself.
    final ring = tester.widget<AppRingButton>(
      find.byWidgetPredicate((widget) => widget is AppRingButton),
    );
    expect(ring.color, AppBrand.mascotGold);
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
    final buttons = tester.widgetList<AppActionButton>(
      find.byWidgetPredicate((widget) => widget is AppActionButton),
    );
    expect(buttons.length, 2);
    // Windows has no ring control: the reload is a full key there.
    expect(
      find.byWidgetPredicate((widget) => widget is AppRingButton),
      findsNothing,
    );
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

final _qrIcons = find.byWidgetPredicate(
  (widget) => widget is AppIcon && widget.icon == AppIcons.qrCode,
);
