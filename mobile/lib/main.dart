import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rive/rive.dart';

import 'app.dart';
import 'core/config.dart';
import 'core/diagnostics/app_log_buffer.dart';
import 'core/diagnostics/diagnostics_service.dart';
import 'core/diagnostics/tunnel_log_prefs.dart';
import 'core/internet_permission.dart';
import 'core/router.dart';
import 'features/vpn/data/windows_tunnel.dart';

void main() async {
  // Required before flutter_secure_storage / path_provider on cold start.
  WidgetsFlutterBinding.ensureInitialized();
  if (io.Platform.isWindows && !WindowsTunnel.acquireSingleInstance()) {
    return;
  }
  final boot = Stopwatch()..start();

  // Level before the first line, then the file, so «Выключены» drops boot too.
  try {
    await TunnelLogPrefs.read();
  } catch (_) {}
  try {
    final dir = await getApplicationSupportDirectory();
    await AppLogBuffer.instance.attachPersistFile(
      io.File('${dir.path}/product.log'),
    );
  } catch (_) {
    // Persist is best-effort; in-memory ring still feeds the log screen.
  }
  AppLogBuffer.instance.debug('app.boot t0 ms=${boot.elapsedMilliseconds}');

  final riveSw = Stopwatch()..start();
  await RiveNative.init();
  AppLogBuffer.instance.debug(
    'app.boot rive.init_ms=${riveSw.elapsedMilliseconds}',
  );

  // Android 17: INTERNET grant (iOS no-op). Do not await discovery here —
  // LaunchScreen stays white until runApp; 8s Dio probes used to block first frame.
  final internetOk = await ensureInternetPermissionGranted();
  AppLogBuffer.instance.debug(
    'app.boot internet_ok=$internetOk ms=${boot.elapsedMilliseconds}',
  );

  final container = ProviderContainer();
  installFlutterErrorHandler();
  AppLogBuffer.instance.debug(
    'app.boot started baseUrl=${AppConfig.baseUrl} ms=${boot.elapsedMilliseconds}',
  );
  if (AppConfig.baseUrl.contains('10.0.2.2')) {
    // ignore: avoid_print
    print(
      '[Proxy Dom] WARNING: 10.0.2.2 только для эмулятора. '
      'Запусти: flutter run --dart-define=APP_ENV=dev (эмулятор) '
      'или без флага / run_prod.ps1 (prod VPS)',
    );
  }

  await AppRouter.warmWelcomeFlag();

  AppLogBuffer.instance.debug(
    'app.boot runApp ms=${boot.elapsedMilliseconds}',
  );
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const ProxyDomApp(),
    ),
  );

  // Bind after the first frame. The utility does not discover an owner API.
  unawaited(_bindUnderlyingAfterFirstFrame(internetOk: internetOk));
}

Future<void> _bindUnderlyingAfterFirstFrame({
  required bool internetOk,
}) async {
  try {
    await bindProcessToUnderlyingNetwork();
  } catch (e) {
    AppLogBuffer.instance.debug('app.boot bind_underlying fail: $e');
  }
  if (!internetOk) {
    AppLogBuffer.instance.debug('app.boot bind skipped: INTERNET denied');
  }
}
