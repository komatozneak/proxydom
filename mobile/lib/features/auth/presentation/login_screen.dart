import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app.dart';
import '../../../../core/router.dart';
import '../../../../l10n/app_localizations.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.loginTitle),
        actions: [
          TextButton(
            onPressed: () {
              // Переключаем на английский (или обратно на русский)
              final next = AppLocale.current.languageCode == 'ru'
                  ? const Locale('en')
                  : const Locale('ru');
              AppLocale.set(next);
              // Чуть уродливо, но для Шага 3 это ок — заставит перерисоваться
              // через смену key в root (см. Шаг 8 где это через Riverpod)
              (context as Element).findAncestorWidgetOfExactType<MaterialApp>();
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  ),
                ),
              );
              Navigator.of(context).pop();
            },
            child: Text(
              AppLocale.current.languageCode.toUpperCase(),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline, size: 64),
            const SizedBox(height: 16),
            Text(l.loginPlaceholderHint),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () {
                AppRouter.setAuthenticated(true);
                context.go('/home');
              },
              child: Text(l.loginTestButton),
            ),
          ],
        ),
      ),
    );
  }
}
