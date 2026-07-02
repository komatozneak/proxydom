import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/app.dart';
import 'package:teremok_connect/core/router.dart';

void main() {
  testWidgets('App boots and shows login screen (en by default)', (tester) async {
    AppLocale.set(const Locale('en'));
    AppRouter.setAuthenticated(false);
    await tester.pumpWidget(const TeremokApp());
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Sign in (test button)'), findsOneWidget);
  });

  testWidgets('App boots and shows login screen (ru)', (tester) async {
    AppLocale.set(const Locale('ru'));
    AppRouter.setAuthenticated(false);
    await tester.pumpWidget(const TeremokApp());
    await tester.pumpAndSettle();

    expect(find.text('Вход'), findsOneWidget);
    expect(find.text('Войти (тестовая кнопка)'), findsOneWidget);
  });

  testWidgets('Tapping login goes to home', (tester) async {
    AppLocale.set(const Locale('ru'));
    AppRouter.setAuthenticated(false);
    await tester.pumpWidget(const TeremokApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Войти (тестовая кнопка)'));
    await tester.pumpAndSettle();

    expect(find.text('Главная'), findsOneWidget);
  });
}
