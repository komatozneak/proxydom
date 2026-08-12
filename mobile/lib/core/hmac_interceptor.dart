import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import 'api_secret_storage.dart';
import 'install_id_storage.dart';

/// Signs `/v2` requests with X-Signature (ADR 009 / 012).
class HmacSignatureInterceptor extends Interceptor {
  HmacSignatureInterceptor({
    ApiSecretStorage? secretStorage,
    InstallIdStorage? installIdStorage,
  })  : _secrets = secretStorage ?? ApiSecretStorage.instance,
        _installIds = installIdStorage ?? InstallIdStorage.instance;

  final ApiSecretStorage _secrets;
  final InstallIdStorage _installIds;
  final _rand = Random.secure();

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final uri = options.uri;
    final path = uri.path;
    if (!path.startsWith('/v2')) {
      handler.next(options);
      return;
    }
    if (_isExempt(path)) {
      handler.next(options);
      return;
    }

    final secret = await _secrets.read();
    if (secret == null || secret.isEmpty) {
      // ADR 012: never send unsigned protected /v2 — force cold register.
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.cancel,
          error: 'hmac_required',
          message: 'Missing api_secret for /v2 HMAC',
        ),
      );
      return;
    }

    final deviceUuid = await _installIds.getOrCreate();
    final timestamp = (DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000)
        .toString();
    final nonce = List.generate(16, (_) => _rand.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

    final bodyBytes = _bodyBytes(options);
    final bodyHash = sha256.convert(bodyBytes).toString();
    final payload =
        '$timestamp\n$nonce\n${options.method.toUpperCase()}\n$path\n$bodyHash';
    final sig = Hmac(sha256, utf8.encode(secret)).convert(utf8.encode(payload));

    options.headers['X-Device-UUID'] = deviceUuid;
    options.headers['X-Timestamp'] = timestamp;
    options.headers['X-Nonce'] = nonce;
    options.headers['X-Signature'] = sig.toString();
    handler.next(options);
  }

  bool _isExempt(String path) {
    const exempt = {
      '/v2/auth/register',
      '/v2/auth/recover',
      '/v2/auth/bootstrap',
      '/v2/auth/refresh',
      '/v2/app/resources',
    };
    return exempt.contains(path);
  }

  List<int> _bodyBytes(RequestOptions options) {
    final data = options.data;
    if (data == null) return <int>[];
    if (data is List<int>) return data;
    if (data is String) return utf8.encode(data);
    return utf8.encode(jsonEncode(data));
  }
}
