import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:teremok_connect/features/vpn/presentation/hy2_import_screen.dart';
import 'package:teremok_connect/l10n/app_localizations.dart';

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
    expect(find.text('Сохранить и подключить'), findsOneWidget);
    expect(find.text('Только сохранить'), findsOneWidget);
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
}
