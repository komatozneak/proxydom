import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Вход')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline, size: 64),
            const SizedBox(height: 16),
            const Text('Login Screen\n(реальная форма — в Шаге 6)'),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () {
                AppRouter.setAuthenticated(true);
                context.go('/home');
              },
              child: const Text('Войти (тестовая кнопка)'),
            ),
          ],
        ),
      ),
    );
  }
}
