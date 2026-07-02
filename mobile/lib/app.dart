import 'package:flutter/material.dart';

import 'core/router.dart';
import 'core/theme.dart';

class TeremokApp extends StatelessWidget {
  const TeremokApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Teremok Connect',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: AppRouter.config,
    );
  }
}
