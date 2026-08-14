import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rive/rive.dart';

import 'app.dart';
import 'core/api_discovery.dart';
import 'core/config.dart';
import 'core/diagnostics/app_log_buffer.dart';
import 'core/diagnostics/diagnostics_service.dart';
import 'core/jwt_interceptor.dart';
import 'core/router.dart';
import 'features/auth/application/auth_provider.dart';
import 'features/auth/application/auth_state.dart';
import 'features/auth/application/logout_handler.dart';
import 'features/beta/application/beta_usage_tracker.dart';

void main() async {
  // Required before flutter_secure_storage / path_provider on cold start.
  WidgetsFlutterBinding.ensureInitialized();
  await RiveNative.init();

  try {
    final dir = await getApplicationSupportDirectory();
    await AppLogBuffer.instance.attachPersistFile(
      io.File('${dir.path}/product.log'),
    );
  } catch (_) {
    // Persist is best-effort; in-memory ring still feeds reports.
  }

  // ADR 009: probe discovery hosts before auth/register.
  try {
    await ApiDiscovery.instance.refreshAndSelect();
  } catch (e) {
    // ignore: avoid_print
    print('[api.discovery] skipped: $e');
  }

  final container = ProviderContainer();
  installFlutterErrorHandler(
    onCrashObserved: () {
      try {
        container.read(betaUsageTrackerProvider).recordCrash();
      } catch (_) {
        // Ignore — container may not be ready.
      }
    },
  );
  AppLogBuffer.instance.info('[app] started baseUrl=${AppConfig.baseUrl}');
  if (AppConfig.baseUrl.contains('10.0.2.2')) {
    // ignore: avoid_print
    print(
      '[Teremok Connect] WARNING: 10.0.2.2 только для эмулятора. '
      'Запусти: flutter run --dart-define=APP_ENV=dev (эмулятор) '
      'или без флага / run_prod.ps1 (prod VPS)',
    );
  }

  // 401 + failed refresh → full logout (tokens already cleared by interceptor).
  SessionExpiredGate.onExpired = () async {
    if (LogoutHandler.inProgress) return;
    AppLogBuffer.instance.warn('[auth] session expired — forcing logout');
    await container.read(logoutHandlerProvider).logout();
  };

  // Warm auth restore before first frame so GoRouter sees tokens on cold start.
  await container.read(authProvider.future);
  await AppRouter.warmWelcomeFlag();

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
