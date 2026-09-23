import 'dart:async';
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
import 'core/internet_permission.dart';
import 'core/ios_store_gates.dart';
import 'core/jwt_interceptor.dart';
import 'core/pair_links.dart';
import 'core/referral_links.dart';
import 'core/router.dart';
import 'core/seat_join_links.dart';
import 'features/auth/application/auth_provider.dart';
import 'features/auth/application/auth_state.dart';
import 'features/auth/application/logout_handler.dart';
import 'features/beta/application/beta_usage_tracker.dart';

void main() async {
  // Required before flutter_secure_storage / path_provider on cold start.
  WidgetsFlutterBinding.ensureInitialized();
  final boot = Stopwatch()..start();

  // Persist first so boot phases land in «Отправить отчёт» even if discovery hangs.
  try {
    final dir = await getApplicationSupportDirectory();
    await AppLogBuffer.instance.attachPersistFile(
      io.File('${dir.path}/product.log'),
    );
  } catch (_) {
    // Persist is best-effort; in-memory ring still feeds reports.
  }
  AppLogBuffer.instance.info('app.boot t0 ms=${boot.elapsedMilliseconds}');

  final riveSw = Stopwatch()..start();
  await RiveNative.init();
  AppLogBuffer.instance.info(
    'app.boot rive.init_ms=${riveSw.elapsedMilliseconds}',
  );

  // Android 17: INTERNET grant (iOS no-op). Do not await discovery here —
  // LaunchScreen stays white until runApp; 8s Dio probes used to block first frame.
  final internetOk = await ensureInternetPermissionGranted();
  AppLogBuffer.instance.info(
    'app.boot internet_ok=$internetOk ms=${boot.elapsedMilliseconds}',
  );

  try {
    await ApiDiscovery.instance.loadCachedOrigin();
  } catch (e) {
    AppLogBuffer.instance.warn('app.boot cache_origin fail: $e');
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
  AppLogBuffer.instance.info(
    'app.boot started baseUrl=${AppConfig.baseUrl} ms=${boot.elapsedMilliseconds}',
  );
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
  // Owner revoked this install on another device → same wipe, no silent
  // re-register (the account may still be recoverable via code/Telegram).
  SessionExpiredGate.onDeviceRevoked = () async {
    if (LogoutHandler.inProgress) return;
    AppLogBuffer.instance.warn('[auth] device revoked — forcing logout');
    await container.read(logoutHandlerProvider).logout();
  };

  // Do not await auth here: Play 0.1.7 sat on the launcher icon for the full
  // register timeout. GoRouter keeps /bootstrap while [authProvider] loads.
  await AppRouter.warmWelcomeFlag();
  if (!hideInAppPlategaCheckout) {
    await attachSeatJoinLinks(container);
    await attachReferralLinks(container);
    await attachPairLinks(container);
  }
  container.read(authProvider);

  // Связываем GoRouter с authProvider: при смене состояния авторизации
  // вызываем refreshNotifier.notifyAuthChanged(), чтобы GoRouter пересчитал redirect.
  container.listen<AsyncValue<AuthState>>(
    authProvider,
    (_, __) => AppRouter.refreshNotifier.notifyAuthChanged(),
    fireImmediately: true,
  );

  AppLogBuffer.instance.info(
    'app.boot runApp ms=${boot.elapsedMilliseconds}',
  );
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const TeremokApp(),
    ),
  );

  // Discovery + bind after first frame (cached origin already applied).
  unawaited(_bootDiscoveryInBackground(internetOk: internetOk, boot: boot));
}

Future<void> _bootDiscoveryInBackground({
  required bool internetOk,
  required Stopwatch boot,
}) async {
  try {
    await bindProcessToUnderlyingNetwork();
  } catch (e) {
    AppLogBuffer.instance.warn('app.boot bind_underlying fail: $e');
  }
  if (!internetOk) {
    AppLogBuffer.instance.warn('app.boot discovery skipped: INTERNET denied');
    return;
  }
  final disc = Stopwatch()..start();
  try {
    final origin = await ApiDiscovery.instance.refreshAndSelect();
    AppLogBuffer.instance.info(
      'app.boot discovery_ms=${disc.elapsedMilliseconds} '
      'origin=${origin ?? 'none'} total_ms=${boot.elapsedMilliseconds}',
    );
  } catch (e) {
    AppLogBuffer.instance.warn(
      'app.boot discovery fail ms=${disc.elapsedMilliseconds}: $e',
    );
  }
}
