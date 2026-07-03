import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config.dart';
import 'core/router.dart';
import 'features/auth/application/auth_provider.dart';
import 'features/auth/application/auth_state.dart';

void main() {
  // Проверочный print — в логах flutter run должно быть:
  //   [Teremok Connect] baseUrl=http://10.0.2.2:8000/api/v1
  // Если для физического Android — adb reverse tcp:8000 tcp:8000 + поменяй baseUrl
  // ignore: avoid_print
  print('[Teremok Connect] baseUrl=${AppConfig.baseUrl}');

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