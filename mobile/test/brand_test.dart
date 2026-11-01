import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/core/theme.dart';
import 'package:proxydom/core/widgets/proxydom_brand.dart';
import 'package:proxydom/core/widgets/window_caption_bar.dart';
import 'package:proxydom/features/shell/presentation/main_shell.dart';
import 'package:proxydom/l10n/app_localizations.dart';

Widget _app(Widget child, {Locale locale = const Locale('ru')}) => MaterialApp(
      theme: AppTheme.dark,
      locale: locale,
      localizationsDelegates: const [
        AppL10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppL10n.supportedLocales,
      home: Scaffold(body: child),
    );

void main() {
  group('the lockup spells the app title', () {
    test('in both languages the app ships', () {
      expect(LockupGrid.of('Прокси Дом'), isNotNull);
      expect(LockupGrid.of('Proxy Dom'), isNotNull);
    });

    test('a title the pixel font cannot spell falls back to text', () async {
      expect(LockupGrid.of('Прокси Хата'), isNull);
      expect(LockupGrid.of('Прокси'), isNull);
    });

    test('the house stands on the line the bitting ends on', () {
      final g = LockupGrid.of('Прокси Дом')!;
      final bottom = g.rows - 1;
      final cols = [
        for (final (c, r) in g.cells.keys)
          if (r == bottom) c
      ]..sort();
      // Teeth at the left end of the blade, and the house's foot at the right,
      // on the same bottom row: one ground line for the whole key.
      expect(cols.first, lessThan(g.columns ~/ 3));
      expect(cols.last, greaterThan(g.columns * 2 ~/ 3));
    });

    testWidgets('it is cut into the drawing, not set as text', (tester) async {
      await tester.pumpWidget(_app(
        const ProxyDomLockup(label: 'Прокси Дом', ink: AppBrand.inkDark),
      ));
      expect(find.text('Прокси Дом'), findsNothing);
      expect(find.bySemanticsLabel('Прокси Дом'), findsOneWidget);
    });
  });

  test('the key never touches the house behind it', () {
    final overlap = Path.combine(
      PathOperation.intersect,
      KeyIconPainter.keyPath(),
      KeyIconPainter.framePath(),
    );
    expect(overlap.getBounds().isEmpty, isTrue);
  });

  group('the Windows pane', () {
    testWidgets('folds to icons and back without overflowing', (tester) async {
      await tester.pumpWidget(_app(Row(children: [
        WindowsNavRail(selected: 1, onSelect: (_) {}),
        const Expanded(child: SizedBox()),
      ])));
      expect(find.byType(ProxyDomLockup), findsOneWidget);
      expect(find.text('Настройки'), findsOneWidget);

      await tester.tap(find.byTooltip('Свернуть панель'));
      for (var t = 0; t < 12; t++) {
        await tester.pump(const Duration(milliseconds: 20));
        expect(tester.takeException(), isNull);
      }
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(WindowsNavRail)).width,
          WindowsNavRail.compactWidth);
      expect(find.text('Настройки'), findsNothing);
      expect(find.byType(ProxyDomKeyIcon), findsOneWidget);

      await tester.tap(find.byTooltip('Развернуть панель'));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(WindowsNavRail)).width,
          WindowsNavRail.width);
      expect(find.text('Настройки'), findsOneWidget);
    });

    testWidgets('selecting an item reports its branch', (tester) async {
      int? picked;
      await tester.pumpWidget(_app(Row(children: [
        WindowsNavRail(selected: 1, onSelect: (i) => picked = i),
        const Expanded(child: SizedBox()),
      ])));
      await tester.tap(find.text('Настройки'));
      expect(picked, MainShell.settingsIndex);
    });
  });

  testWidgets('the caption names the window next to the app icon',
      (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('proxydom/window_chrome'),
      (call) async => null,
    );
    await tester.pumpWidget(_app(
      const WindowCaptionBar(label: 'Прокси Дом', ink: AppBrand.inkDark),
    ));
    await tester.pump();
    expect(find.text('Прокси Дом'), findsOneWidget);
    expect(find.byType(ProxyDomKeyIcon), findsOneWidget);
  });
}
