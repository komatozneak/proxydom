import 'package:flutter/foundation.dart';
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

  testWidgets('a lone vless key is refused off Android', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await _pumpImport(tester);
      await tester.enterText(
        find.byType(TextField),
        'vless://11111111-1111-1111-1111-111111111111@203.0.113.10:443'
        '?security=tls&type=ws&path=%2Fws#A',
      );
      await tester.pump();

      expect(
        find.text(
          'Не удалось добавить узел: этот протокол не запускается на этом устройстве.',
        ),
        findsOneWidget,
      );
      expect(_saveEnabled(tester), isFalse);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('a lone vless key is accepted on Android', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await _pumpImport(tester);
      await tester.enterText(
        find.byType(TextField),
        'vless://11111111-1111-1111-1111-111111111111@203.0.113.10:443'
        '?security=tls&type=ws&path=%2Fws#A',
      );
      await tester.pump();

      expect(
        find.text(
          'Не удалось добавить узел: этот протокол не запускается на этом устройстве.',
        ),
        findsNothing,
      );
      expect(_saveEnabled(tester), isTrue);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('a lone parked key is refused on Android', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await _pumpImport(tester);
      await tester.enterText(
        find.byType(TextField),
        'trojan://secret@203.0.113.10:443#A',
      );
      await tester.pump();

      expect(
        find.text(
          'Не удалось добавить узел: этот протокол не запускается на этом устройстве.',
        ),
        findsOneWidget,
      );
      expect(_saveEnabled(tester), isFalse);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('a lone vless Reality key stays inactive on Android', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await _pumpImport(tester);
      await tester.enterText(
        find.byType(TextField),
        'vless://11111111-1111-1111-1111-111111111111@203.0.113.10:443'
        '?security=reality&sni=www.example.com&pbk=PUBLIC&sid=ab#R',
      );
      await tester.pump();

      expect(
        find.text(
          'Не удалось добавить узел: этот протокол не запускается на этом устройстве.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Подключение недоступно (протокол не поддерживается клиентом).',
        ),
        findsOneWidget,
      );
      expect(_saveEnabled(tester), isFalse);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

Future<void> _pumpImport(WidgetTester tester) async {
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
}

bool _saveEnabled(WidgetTester tester) {
  return tester
          .widget<AppActionButton>(
            find.widgetWithText(AppActionButton, 'Сохранить'),
          )
          .onPressed !=
      null;
}
