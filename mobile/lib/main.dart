import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config.dart';
import 'core/router.dart';
import 'features/auth/application/auth_provider.dart';
import 'features/auth/application/auth_state.dart';

void main() {
  // ignore: avoid_print
  print('[Teremok Connect] baseUrl=${AppConfig.baseUrl}');
  if (AppConfig.baseUrl.contains('10.0.2.2')) {
    // ignore: avoid_print
    print(
      '[Teremok Connect] WARNING: 10.0.2.2 только для эмулятора. '
      'Запусти: flutter run --dart-define=APP_ENV=dev (эмулятор) '
      'или без флага / run_prod.ps1 (prod VPS)',
    );
  }

  final container = ProviderContainer();

  // Связываем GoRouter с authProvider: при смене состояния авторизации
  // вызываем refreshNotifier.notifyAuthChanged(), чтобы GoRouter пересчитал redirect.
  container.listen<AsyncValue<AuthState>>(
    authProvider,
    (_, __) => AppRouter.refreshNotifier.notifyAuthChanged(),
    fireImmediately: false,
  );

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const TeremokApp(),
    ),
  );
}