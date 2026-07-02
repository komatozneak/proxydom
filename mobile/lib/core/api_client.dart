import 'package:dio/dio.dart';

import 'config.dart';
import 'token_storage.dart';

/// Единый экземпляр Dio с предустановленными интерсепторами.
///
/// На этом шаге подключены:
/// - Logging interceptor (logger через dio logger)
/// - Auth interceptor (читает access_token из TokenStorage и добавляет в Authorization header)
///
/// На Шаге 5 добавим JwtRefreshInterceptor с мьютексом для 401 → refresh.
class ApiClient {
  ApiClient._();

  static final Dio instance = _build();

  static Dio _build() {
    final dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.baseUrl,
        connectTimeout: AppConfig.connectTimeout,
        receiveTimeout: AppConfig.receiveTimeout,
        contentType: 'application/json',
        responseType: ResponseType.json,
        // НЕ бросать на 4xx — обрабатываем сами (для refresh-логики)
        validateStatus: (status) => status != null && status < 500,
      ),
    );

    dio.interceptors.add(_authInterceptor());
    dio.interceptors.add(
      LogInterceptor(
        requestBody: false,
        responseBody: false,
        requestHeader: false,
        responseHeader: false,
        logPrint: (obj) {
          // Простой логгер через debugPrint — потом заменим на пакет
          // (для MVP можно использовать dart:developer)
          // ignore: avoid_print
          print(obj);
        },
      ),
    );

    return dio;
  }

  static Interceptor _authInterceptor() => InterceptorsWrapper(
        onRequest: (options, handler) async {
          // Если есть access_token — прикрепляем к запросу
          final token = await TokenStorage.instance.readAccessToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
      );
}
