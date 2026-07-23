import 'package:flutter/material.dart';

import 'core/router.dart';
import 'core/theme.dart';
import 'core/updates/update_check_service.dart';
import 'l10n/app_localizations.dart';

/// Текущий язык приложения. Хранится пока в памяти.
/// В Шаге 11 заменим на Riverpod + secure_storage.
class AppLocale {
  AppLocale._();

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
      builder: (context, child) {
        return _UpdateCheckHost(child: child ?? const SizedBox.shrink());
      },
    );
  }
}

/// Runs a one-shot soft update check after the first frame (does not block auth).
class _UpdateCheckHost extends StatefulWidget {
  const _UpdateCheckHost({required this.child});

  final Widget child;

  @override
  State<_UpdateCheckHost> createState() => _UpdateCheckHostState();
}

class _UpdateCheckHostState extends State<_UpdateCheckHost> {
  var _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      UpdateCheckService().maybePrompt(context);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
