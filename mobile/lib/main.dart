import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config.dart';
import 'core/diagnostics/app_log_buffer.dart';
import 'core/diagnostics/diagnostics_service.dart';
import 'core/router.dart';
import 'features/auth/application/auth_provider.dart';
import 'features/auth/application/auth_state.dart';

void main() async {
  // Required before flutter_secure_storage / path_provider on cold start.
  WidgetsFlutterBinding.ensureInitialized();
  installFlutterErrorHandler();
  AppLogBuffer.instance.info('[app] started baseUrl=${AppConfig.baseUrl}');
  if (AppConfig.baseUrl.contains('10.0.2.2')) {
    // ignore: avoid_print
    print(
      '[Teremok Connect] WARNING: 10.0.2.2 только для эмулятора. '
      'Запусти: flutter run --dart-define=APP_ENV=dev (эмулятор) '
      'или без флага / run_prod.ps1 (prod VPS)',
    );
  }

  final container = ProviderContainer();

  // Warm auth restore before first frame so GoRouter sees tokens on cold start.
  await container.read(authProvider.future);

  // Связываем GoRouter с authProvider: при смене состояния авторизации
  // вызываем refreshNotifier.notifyAuthChanged(), чтобы GoRouter пересчитал redirect.
  container.listen<AsyncValue<AuthState>>(
    authProvider,
    (_, __) => AppRouter.refreshNotifier.notifyAuthChanged(),
    fireImmediately: true,
  );

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const TeremokApp(),
    ),
  );
}
