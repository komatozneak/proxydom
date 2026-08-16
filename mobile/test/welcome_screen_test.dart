import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:teremok_connect/core/theme.dart';
import 'package:teremok_connect/features/onboarding/presentation/welcome_screen.dart';
import 'package:teremok_connect/l10n/app_localizations.dart';

void main() {
  testWidgets('Welcome offers a restore entry point (post-logout landing)',
      (tester) async {
    final router = GoRouter(
      initialLocation: '/welcome',
      routes: [
        GoRoute(path: '/welcome', builder: (_, __) => const WelcomeScreen()),
        GoRoute(
          path: '/restore',
          builder: (_, __) => const Scaffold(body: Text('restore-stub')),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.light,
        locale: const Locale('ru'),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();

    final l10n = await AppL10n.delegate.load(const Locale('ru'));
    final restoreLink = find.text(l10n.restoreTitle);
    expect(restoreLink, findsOneWidget);

    await tester.tap(restoreLink);
    await tester.pumpAndSettle();
    expect(find.text('restore-stub'), findsOneWidget);
  });
}
