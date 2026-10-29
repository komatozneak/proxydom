import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:proxydom/features/vpn/data/hy2_import_store.dart';
import 'package:proxydom/features/vpn/data/subscription_device.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    subscriptionHeaderSource = () async => {};
  });

  tearDown(() {
    subscriptionHeaderSource = loadSubscriptionDeviceHeaders;
    hy2HttpClientFactory = HttpClient.new;
  });

  test('refreshing a document GETs /api/v1/sub/{token} again', () async {
    final paths = <String>[];
    const token = 'AbCdEfGh12345678';
    const line =
        'hysteria2://user:pass@203.0.113.12:443/?sni=c.example#Charlie';
    hy2HttpClientFactory = () => _RecordingClient(paths, line);
    final url = 'http://127.0.0.1/api/v1/sub/$token';
    final store = Hy2ImportStore.instance;
    await store.seedForTest([
      ShareCatalog(
        id: 'catalog-key',
        title: 'Прокси Дом',
        lines: [line],
        url: url,
      ),
    ]);

    final outcome = await store.refreshCatalog('catalog-key');
    expect(outcome.kind, ShareRefreshKind.updated);
    expect(paths, ['GET /api/v1/sub/$token']);
  });

  test('304 does not move the quota freshness date', () async {
    const line =
        'hysteria2://user:pass@203.0.113.12:443/?sni=c.example#Charlie';
    const old = '2026-10-01T09:00:00Z';
    hy2HttpClientFactory = () => _StaticClient(
          status: HttpStatus.notModified,
          body: '',
          headers: const {},
        );
    final store = Hy2ImportStore.instance;
    await store.seedForTest([
      ShareCatalog(
        id: 'catalog-key',
        title: 'Профиль',
        lines: [line],
        url: 'http://127.0.0.1/api/v1/sub/token',
        trafficMeta: 'upload=0; download=1; total=10',
        trafficUpdatedAt: old,
        lastUpdated: old,
      ),
    ]);

    final outcome = await store.refreshCatalog('catalog-key');
    final saved = (await store.catalogs()).single;
    expect(outcome.kind, ShareRefreshKind.unchanged);
    expect(saved.lastUpdated, old);
    expect(saved.trafficUpdatedAt, old);
  });

  test('an empty userinfo response keeps the old traffic date', () async {
    const line =
        'hysteria2://user:pass@203.0.113.12:443/?sni=c.example#Charlie';
    const old = '2026-10-01T09:00:00Z';
    hy2HttpClientFactory = () => _StaticClient(
          status: HttpStatus.ok,
          body: line,
          headers: const {'profile-title': 'Профиль'},
        );
    final store = Hy2ImportStore.instance;
    await store.seedForTest([
      ShareCatalog(
        id: 'catalog-key',
        title: 'Профиль',
        lines: [line],
        url: 'http://127.0.0.1/api/v1/sub/token',
        trafficMeta: 'upload=0; download=1; total=10',
        trafficUpdatedAt: old,
        lastUpdated: old,
      ),
    ]);

    await store.refreshCatalog('catalog-key');
    final saved = (await store.catalogs()).single;
    expect(saved.trafficMeta, 'upload=0; download=1; total=10');
    expect(saved.trafficUpdatedAt, old);
    expect(saved.lastUpdated, isNot(old));
  });
}

class _RecordingClient extends Fake implements HttpClient {
  _RecordingClient(this.paths, this.body);

  final List<String> paths;
  final String body;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    paths.add('GET ${url.path}');
    return _RecordingRequest(body);
  }

  @override
  void close({bool force = false}) {}
}

class _StaticClient extends Fake implements HttpClient {
  _StaticClient({
    required this.status,
    required this.body,
    required this.headers,
  });

  final int status;
  final String body;
  final Map<String, String> headers;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    return _StaticRequest(
      status: status,
      body: body,
      responseHeaders: headers,
    );
  }

  @override
  void close({bool force = false}) {}
}

class _StaticRequest extends Fake implements HttpClientRequest {
  _StaticRequest({
    required this.status,
    required this.body,
    required this.responseHeaders,
  });

  final int status;
  final String body;
  final Map<String, String> responseHeaders;
  final _headers = _RecordingHeaders();

  @override
  HttpHeaders get headers => _headers;

  @override
  Future<HttpClientResponse> close() async => _RecordingResponse(
        status: status,
        body: body,
        headers: responseHeaders,
      );
}

class _RecordingRequest extends Fake implements HttpClientRequest {
  _RecordingRequest(this.body);

  final String body;
  final _headers = _RecordingHeaders();

  @override
  HttpHeaders get headers => _headers;

  @override
  Future<HttpClientResponse> close() async => _RecordingResponse(body: body);
}

class _RecordingResponse extends Fake implements HttpClientResponse {
  _RecordingResponse({
    this.status = HttpStatus.ok,
    required this.body,
    Map<String, String> headers = const {},
  }) : _headers = _RecordingHeaders(headers);

  final int status;
  final String body;
  final _RecordingHeaders _headers;

  @override
  int get statusCode => status;

  @override
  Future<E> drain<E>([E? futureValue]) async {
    if (futureValue == null) return null as E;
    return futureValue;
  }

  @override
  HttpHeaders get headers => _headers;

  @override
  Stream<S> transform<S>(StreamTransformer<List<int>, S> streamTransformer) {
    return Stream<List<int>>.value(utf8.encode(body))
        .transform(streamTransformer);
  }
}

class _RecordingHeaders extends Fake implements HttpHeaders {
  _RecordingHeaders([Map<String, String> values = const {}])
      : _values = {
          for (final entry in values.entries)
            entry.key.toLowerCase(): entry.value,
        };

  final Map<String, String> _values;

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  String? value(String name) => _values[name.toLowerCase()];
}
