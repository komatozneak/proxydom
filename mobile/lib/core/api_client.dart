import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

import 'config.dart';
import 'hmac_interceptor.dart';
import 'jwt_interceptor.dart';
import 'token_storage.dart';
import 'v2_path_interceptor.dart';

/// Единый экземпляр Dio с предустановленными интерсепторами.
class ApiClient {
  ApiClient._();

  static final Dio instance = _build();
  static Dio? _refreshClient;

  static bool isControlPlaneHost(String host) {
    final h = host.trim().toLowerCase();
    return h == 'api.teremokconnect.online' ||
        h == 'api2.teremokconnect.online' ||
        h == 'teremokconnect.online' ||
        h.endsWith('.teremokconnect.online');
  }

  /// Discovery failover: switch Dio base to `{origin}/v2` (or legacy `/api/v1`).
  static void setBaseOrigin(String origin) {
    final base = AppConfig.baseUrlForOrigin(origin);
    instance.options.baseUrl = base;
    _refreshClient?.options.baseUrl = base;
  }

  static Dio _build() {
    final refreshClient = Dio(
      BaseOptions(
        baseUrl: AppConfig.baseUrl,
        connectTimeout: AppConfig.connectTimeout,
        receiveTimeout: AppConfig.receiveTimeout,
        contentType: 'application/json',
        responseType: ResponseType.json,
        validateStatus: (status) => status != null && status < 500,
      ),
    );
    _refreshClient = refreshClient;
    configureSignedRetryClient(refreshClient);

    final dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.baseUrl,
        connectTimeout: AppConfig.connectTimeout,
        receiveTimeout: AppConfig.receiveTimeout,
        contentType: 'application/json',
        responseType: ResponseType.json,
        // 4xx обрабатываем сами (для refresh-логики), 5xx — как ошибки
        validateStatus: (status) => status != null && status < 500,
      ),
    );

    dio.interceptors.add(V2PathInterceptor());
    dio.interceptors.add(HmacSignatureInterceptor());

    dio.interceptors.add(
      JwtRefreshInterceptor(
        dio: dio,
        refreshEndpoint: 'auth/refresh',
        tokenStorage: TokenStorage.instance,
        refreshClient: refreshClient,
      ),
    );

    if (shouldInstallHttpLogging(isDebugMode: kDebugMode)) {
      dio.interceptors.add(
        LogInterceptor(
          requestBody: false,
          responseBody: false,
          requestHeader: false,
          responseHeader: true,
          logPrint: (value) => debugPrint(value.toString()),
        ),
      );
    }

    return dio;
  }

  /// The refresh client also performs the post-refresh retry. It must remap
  /// and re-sign that request so nonce replay protection never sees the stale
  /// X-Nonce/X-Signature copied from the original 401.
  @visibleForTesting
  static void configureSignedRetryClient(Dio client) {
    client.interceptors.add(V2PathInterceptor());
    client.interceptors.add(HmacSignatureInterceptor());
  }

  @visibleForTesting
  static bool shouldInstallHttpLogging({required bool isDebugMode}) =>
      isDebugMode;

  /// Play 0.1.7 hung on a custom IP-pinned [SecureSocket] factory.
  /// Auth and discovery must share the default OS TLS stack.
  @visibleForTesting
  static bool usesDefaultTlsTransport(Dio client) {
    final adapter = client.httpClientAdapter;
    if (adapter is! IOHttpClientAdapter) return false;
    return adapter.createHttpClient == null;
  }

  /// POST with the longer auth timeout budget used by bootstrap/recovery flows.
  static Future<Response<dynamic>> postAuth(
    String path, {
    Object? data,
  }) {
    return instance.post(
      path,
      data: data,
      options: Options(
        connectTimeout: AppConfig.authConnectTimeout,
        receiveTimeout: AppConfig.authReceiveTimeout,
      ),
    );
  }
}
