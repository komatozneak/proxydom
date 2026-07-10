import 'package:dio/dio.dart';

import 'config.dart';
import 'jwt_interceptor.dart';
import 'token_storage.dart';

/// Единый экземпляр Dio с предустановленными интерсепторами.
class ApiClient {
  ApiClient._();

  static final Dio instance = _build();

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

    dio.interceptors.add(
      JwtRefreshInterceptor(
        dio: dio,
        refreshEndpoint: 'auth/refresh',
        tokenStorage: TokenStorage.instance,
        refreshClient: refreshClient,
      ),
    );

    dio.interceptors.add(
      LogInterceptor(
        requestBody: false,
        responseBody: false,
        requestHeader: false,
        responseHeader: false,
        logPrint: (obj) {
          // ignore: avoid_print
          print(obj);
        },
      ),
    );

    return dio;
  }

  /// POST с увеличенным таймаутом для flash-call (Zvonok на backend).
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
