import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/app.dart';
import 'package:teremok_connect/core/router.dart';

void main() {
  testWidgets('App boots and shows login screen', (tester) async {
    // Сбросить в неавторизованное состояние для детерминированного теста
    AppRouter.setAuthenticated(false);
    await tester.pumpWidget(const TeremokApp());
    await tester.pumpAndSettle();

    expect(find.text('Вход'), findsOneWidget);
    expect(find.text('Войти (тестовая кнопка)'), findsOneWidget);
  });

  testWidgets('Tapping login goes to home', (tester) async {
    AppRouter.setAuthenticated(false);
    await tester.pumpWidget(const TeremokApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Войти (тестовая кнопка)'));
    await tester.pumpAndSettle();

    expect(find.text('Главная'), findsOneWidget);
  });
}
