import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:proxydom/core/widgets/app_action_button.dart';
import 'package:proxydom/features/vpn/presentation/hy2_import_screen.dart';
import 'package:proxydom/l10n/app_localizations.dart';

void main() {
  testWidgets('add screen stays inside the keyboard inset', (tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Hy2ImportScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          routerConfig: router,
          locale: const Locale('ru'),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          builder: (context, child) {
            final media = MediaQuery.of(context);
            return MediaQuery(
              data: media.copyWith(
                viewInsets: const EdgeInsets.only(bottom: 360),
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Сохранить'), findsOneWidget);
    expect(find.text('Только сохранить'), findsNothing);
  });

  testWidgets('a bad draft says the link was not read', (tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Hy2ImportScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          routerConfig: router,
          locale: const Locale('ru'),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
        ),
      ),
    );
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'not-a-link');
    await tester.pump();

    expect(find.text('Ссылка не разобрана'), findsOneWidget);
    expect(find.text('Ошибка подключения'), findsNothing);
  });

  testWidgets('a lone vless key is not added', (tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Hy2ImportScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          routerConfig: router,
          locale: const Locale('ru'),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
        ),
      ),
    );
    await tester.pump();
    await tester.enterText(
      find.byType(TextField),
      'vless://11111111-1111-1111-1111-111111111111@203.0.113.10:443#A',
    );
    await tester.pump();

    expect(
      find.text(
        'Не удалось добавить узел: поддерживается только протокол Hysteria2.',
      ),
      findsOneWidget,
    );
    // The keys are AppActionButton now, not Material buttons: the save key
    // must stay dead while the draft has nothing Hy2 in it.
    expect(
      tester
          .widget<AppActionButton>(
            find.widgetWithText(AppActionButton, 'Сохранить'),
          )
          .onPressed,
      isNull,
    );
  });
}
