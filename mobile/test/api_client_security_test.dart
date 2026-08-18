import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/core/api_client.dart';

import 'helpers/secure_storage_mock.dart';

class _RecordingAdapter implements HttpClientAdapter {
  final requests = <Map<String, dynamic>>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add({
      'path': options.uri.path,
      'headers': Map<String, dynamic>.from(options.headers),
    });
    return ResponseBody.fromString(
      '{}',
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('signed retry client overwrites stale HMAC headers with a new nonce',
      () async {
    final secure = mockSecureStorage()
      ..['tc.api_secret'] = 'retry-test-api-secret'
      ..['tc.install_id'] = '11111111-2222-4333-8444-555555555555';
    expect(secure, isNotEmpty);

    final dio = Dio(
      BaseOptions(baseUrl: 'https://api.teremokconnect.online:8443/v2'),
    );
    final adapter = _RecordingAdapter();
    dio.httpClientAdapter = adapter;
    ApiClient.configureSignedRetryClient(dio);

    const stale = {
      'X-Device-UUID': 'stale-device',
      'X-Timestamp': '1',
      'X-Nonce': 'stale-nonce',
      'X-Signature': 'stale-signature',
    };
    await dio.get<dynamic>('app/me', options: Options(headers: stale));
    await dio.get<dynamic>('app/me', options: Options(headers: stale));

    final first = adapter.requests[0]['headers'] as Map<String, dynamic>;
    final second = adapter.requests[1]['headers'] as Map<String, dynamic>;
    expect(adapter.requests[0]['path'], '/v2/app/me');
    expect(first['X-Device-UUID'], '11111111-2222-4333-8444-555555555555');
    expect(first['X-Nonce'], isNot('stale-nonce'));
    expect(first['X-Signature'], isNot('stale-signature'));
    expect(second['X-Nonce'], isNot(first['X-Nonce']));
    expect(second['X-Signature'], isNot(first['X-Signature']));
  });

  test('release builds never install HTTP header logging', () {
    expect(
      ApiClient.shouldInstallHttpLogging(isDebugMode: false),
      isFalse,
    );
    expect(
      ApiClient.shouldInstallHttpLogging(isDebugMode: true),
      isTrue,
    );
  });

  test('control-plane Dio uses default TLS, not a pinned SecureSocket factory',
      () {
    expect(ApiClient.usesDefaultTlsTransport(ApiClient.instance), isTrue);
    final refresh = Dio(
      BaseOptions(baseUrl: 'https://api.teremokconnect.online:8443/v2'),
    );
    expect(ApiClient.usesDefaultTlsTransport(refresh), isTrue);
  });

  test('primary Dio keeps v2 remap, HMAC, and JWT refresh interceptors', () {
    final types = ApiClient.instance.interceptors
        .map((interceptor) => interceptor.runtimeType.toString())
        .toList();
    expect(types, contains('V2PathInterceptor'));
    expect(types, contains('HmacSignatureInterceptor'));
    expect(types, contains('JwtRefreshInterceptor'));
  });
}
