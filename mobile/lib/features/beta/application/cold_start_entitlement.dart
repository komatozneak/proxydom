import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config.dart';
import '../../../core/diagnostics/app_log_buffer.dart';
import '../../../core/ios_store_gates.dart';
import '../../../core/router.dart';
import '../../auth/application/auth_provider.dart';
import '../../auth/application/auth_state.dart';
import '../../auth/application/logout_handler.dart';
import '../data/jwt_subject.dart';
import 'beta_providers.dart';
import 'post_auth_router.dart';

/// Soft entitlement after JWT cold-start lands on Home (no full-screen /gate).
///
/// Never stops the Packet Tunnel. Redirects only for promo / locked /
/// onboarding / 401. Network failures stay on Home (VPN may still be up).
class ColdStartEntitlement {
  ColdStartEntitlement._();

  static bool _started = false;

  @visibleForTesting
  static void resetForTest() {
    _started = false;
  }

  /// Fire-and-forget once per process after shell mounts.
  static Future<void> runOnce(WidgetRef ref, BuildContext context) async {
    if (_started) return;
    _started = true;
    if (freeKeyClient) {
      AppLogBuffer.instance.debug('cold_start.entitlement skip free client');
      return;
    }
    AppLogBuffer.instance.debug('cold_start.entitlement begin');

    final auth = ref.read(authProvider).valueOrNull;
    if (auth is! AuthStateAuthenticated) {
      AppLogBuffer.instance.debug('cold_start.entitlement skip unauthed');
      return;
    }

    final userId = jwtSubject(auth.accessToken) ?? 'unknown';
    try {
      final entitlement = await ref.read(betaApiProvider).fetchEntitlement();
      if (!context.mounted) return;
      final dest = await PostAuthRouter.resolveWithPrefs(
        entitlement: entitlement,
        userId: userId,
      );
      AppLogBuffer.instance.debug('cold_start.entitlement dest=${dest.name}');
      if (!context.mounted) return;
      switch (dest) {
        case PostAuthDestination.home:
        case PostAuthDestination.onboarding:
        case PostAuthDestination.promo:
        case PostAuthDestination.locked:
          return;
      }
    } on DioException catch (e) {
      AppLogBuffer.instance.debug(
        'cold_start.entitlement fail type=${e.type.name} '
        'status=${e.response?.statusCode ?? '-'}',
      );
      if (e.response?.statusCode == 401) {
        if (!context.mounted) return;
        AppRouter.postAuthResolved = false;
        if (AppConfig.authAnonymous) {
          await ref.read(authProvider.notifier).retryBootstrap();
          if (context.mounted) context.go('/gate');
          return;
        }
        await ref.read(logoutHandlerProvider).logout();
        if (context.mounted) context.go('/login');
      }
      // Transient network: stay on Home; excludeRoute / LTE will retry later.
    } catch (e) {
      AppLogBuffer.instance.debug('cold_start.entitlement fail err=$e');
    }
  }
}
