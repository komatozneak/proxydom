import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/app.dart';
import 'package:teremok_connect/core/api_client.dart';
import 'package:teremok_connect/core/config.dart';
import 'package:teremok_connect/core/router.dart';
import 'package:teremok_connect/core/token_storage.dart';

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

  test('AppConfig.baseUrl is set to Android emulator default', () {
    expect(AppConfig.baseUrl, isNotEmpty);
    expect(AppConfig.baseUrl, contains('/api/v1'));
  });

  test('ApiClient has correct base URL', () {
    expect(ApiClient.instance.options.baseUrl, AppConfig.baseUrl);
  });

  test('TokenStorage can be cleared safely on empty storage', () async {
    // Просто проверяем что вызов не падает
    await TokenStorage.instance.clear();
  });
}
