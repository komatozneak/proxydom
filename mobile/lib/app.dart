import 'package:flutter/material.dart';

import 'core/router.dart';
import 'core/theme.dart';
import 'l10n/app_localizations.dart';

/// Текущий язык приложения. Хранится пока в памяти.
/// В более позднем шаге заменим на Riverpod + secure_storage.
class AppLocale {
  static Locale _current = const Locale('ru');

  static Locale get current => _current;

  static void set(Locale locale) {
    _current = locale;
  }

  static const supportedLocales = [
    Locale('en'),
    Locale('ru'),
  ];
}

class TeremokApp extends StatelessWidget {
  const TeremokApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Teremok Connect',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      locale: AppLocale.current,
      supportedLocales: AppLocale.supportedLocales,
      localizationsDelegates: AppL10n.localizationsDelegates,
      routerConfig: AppRouter.config,
    );
  }
}
