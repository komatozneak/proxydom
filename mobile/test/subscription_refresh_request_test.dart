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
    const line = 'hysteria2://user:pass@203.0.113.12:443/?sni=c.example#Charlie';
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

class _RecordingRequest extends Fake implements HttpClientRequest {
  _RecordingRequest(this.body);

  final String body;
  final _headers = _RecordingHeaders();

  @override
  HttpHeaders get headers => _headers;

  @override
  Future<HttpClientResponse> close() async => _RecordingResponse(body);
}

class _RecordingResponse extends Fake implements HttpClientResponse {
  _RecordingResponse(this.body);

  final String body;
  final _headers = _RecordingHeaders();

  @override
  int get statusCode => HttpStatus.ok;

  @override
  HttpHeaders get headers => _headers;

  @override
  Stream<S> transform<S>(StreamTransformer<List<int>, S> streamTransformer) {
    return Stream<List<int>>.value(utf8.encode(body)).transform(streamTransformer);
  }
}

class _RecordingHeaders extends Fake implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  String? value(String name) => null;
}
