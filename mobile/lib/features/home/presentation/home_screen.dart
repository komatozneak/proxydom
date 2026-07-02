import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app.dart';
import '../../../../core/router.dart';
import '../../../../l10n/app_localizations.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.homeTitle),
        actions: [
          TextButton(
            onPressed: () {
              final next = AppLocale.current.languageCode == 'ru'
                  ? const Locale('en')
                  : const Locale('ru');
              AppLocale.set(next);
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
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: l.logoutTooltip,
            onPressed: () {
              AppRouter.setAuthenticated(false);
              context.go('/login');
            },
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.shield_outlined, size: 96, color: Colors.teal),
            const SizedBox(height: 24),
            Text(
              l.homeVpnHint,
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
