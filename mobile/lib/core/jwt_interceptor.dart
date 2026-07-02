import 'dart:async';

import 'package:dio/dio.dart';

import 'token_storage.dart';

/// Перехватчик 401-ответов с автоматической ротацией токенов.
class JwtRefreshInterceptor extends QueuedInterceptor {
  JwtRefreshInterceptor({
    required this.dio,
    required this.refreshEndpoint,
    required this.tokenStorage,
    Dio? refreshClient,
  }) : _refreshClient = refreshClient ?? Dio();

  final Dio dio;
  final String refreshEndpoint;
  final TokenStore tokenStorage;
  final Dio _refreshClient;

  Future<bool>? _ongoingRefresh;

  Future<bool> _doRefresh(String refreshToken) async {
    try {
      final baseUrl = _refreshClient.options.baseUrl;
      final normalizedBase = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
      final refreshUrl = '$normalizedBase$refreshEndpoint';

      final resp = await _refreshClient.post<Map<String, dynamic>>(
        refreshUrl,
        data: {'refresh_token': refreshToken},
        options: Options(
          receiveTimeout: const Duration(seconds: 8),
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      if (resp.statusCode != null &&
          resp.statusCode! >= 200 &&
          resp.statusCode! < 300 &&
          resp.data is Map) {
        final data = Map<String, dynamic>.from(resp.data! as Map);
        final newAccess = data['access_token'] as String?;
        final newRefresh = data['refresh_token'] as String?;
        if (newAccess != null && newRefresh != null) {
          await tokenStorage.saveTokens(
            accessToken: newAccess,
            refreshToken: newRefresh,
          );
          return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _refreshOnce() async {
    final completer = _ongoingRefresh ??= _doRefreshInternal().then((ok) {
      _ongoingRefresh = null;
      return ok;
    });
    return completer;
  }

  Future<bool> _doRefreshInternal() async {
    final refreshToken = await tokenStorage.readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      return false;
    }
    return _doRefresh(refreshToken);
  }

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await tokenStorage.readAccessToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) async {
    if (response.statusCode != 401 || _isRefreshPath(response.requestOptions)) {
      return handler.next(response);
    }

    final retried = response.requestOptions.extra['jwt_retried'] == true;
    if (retried) {
      return handler.next(response);
    }

    final ok = await _refreshOnce();
    if (!ok) {
      await tokenStorage.clear();
      return handler.next(response);
    }

    final newAccess = await tokenStorage.readAccessToken();
    final retryOptions = response.requestOptions.copyWith(
      extra: Map<String, dynamic>.from(response.requestOptions.extra)
        ..['jwt_retried'] = true,
      headers: Map<String, dynamic>.from(response.requestOptions.headers)
        ..['Authorization'] = 'Bearer ${newAccess ?? ''}',
    );

    try {
      // Retry вне текущего interceptor-стека (Dio блокирует вложенные fetch/get).
      final retryResp = await Future<Response<dynamic>>.microtask(
        () => _refreshClient.fetch<dynamic>(retryOptions),
      );
      return handler.resolve(retryResp);
    } catch (e) {
      return handler.reject(
        DioException(
          requestOptions: response.requestOptions,
          error: e,
        ),
      );
    }
  }

  bool _isRefreshPath(RequestOptions options) {
    return options.path.contains(refreshEndpoint) ||
        options.uri.path.endsWith('/$refreshEndpoint');
  }
}
