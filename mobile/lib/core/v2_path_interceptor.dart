import 'package:dio/dio.dart';

import 'config.dart';

/// Remaps legacy `/api/v1`-shaped paths onto `/v2` Ogon-parity routes (ADR 009).
class V2PathInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (!AppConfig.useV2Api) {
      handler.next(options);
      return;
    }
    final path = options.path;
    final mapped = mapLegacyPath(path);
    if (mapped != null) {
      options.path = mapped;
    }
    // Endpoints that remain on /api/v1 only.
    if (_staysOnV1(path) || _staysOnV1(mapped ?? path)) {
      final origin = AppConfig.resolveApiOrigin(AppConfig.baseUrl);
      options.baseUrl = '$origin/api/v1';
      // Strip accidental /v2 prefix if map didn't change a v1-only path.
      if (options.path.startsWith('/v2/')) {
        options.path = options.path.substring(3);
      }
    }
    handler.next(options);
  }

  static bool _staysOnV1(String path) {
    return path.contains('/billing/subscription') ||
        path.contains('/billing/platega/status') ||
        path.contains('/beta/') ||
        path.contains('/support') ||
        path.contains('/app/version');
  }

  /// Returns remapped path (leading slash) or null if unchanged.
  static String? mapLegacyPath(String path) {
    if (path.contains('/app/connect/get/v3') ||
        path.contains('/app/nodes/v2') ||
        path.contains('/app/resources') ||
        path.contains('/app/plans') ||
        path.contains('/app/payments') ||
        path.contains('/app/usage') ||
        path.contains('/app/me')) {
      return null;
    }
    if (path == '/vpn/config' || path.endsWith('/vpn/config')) {
      return '/app/connect/get/v3';
    }
    if (path == '/vpn/nodes' || path.endsWith('/vpn/nodes')) {
      return '/app/nodes/v2';
    }
    if (path.startsWith('/seats/') || path == '/seats') {
      return '/app$path';
    }
    if (path.startsWith('/devices/') || path == '/devices') {
      return '/app$path';
    }
    if (path == '/me' || path.endsWith('/me')) {
      return '/app/me';
    }
    if (path == '/billing/platega/create' ||
        path.endsWith('/billing/platega/create')) {
      return '/app/payments';
    }
    // auth/register, auth/recover, auth/refresh stay under /v2/auth/*
    return null;
  }
}
