import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:proxydom/features/vpn/data/hy2_import_store.dart';
import 'package:proxydom/features/vpn/data/route_document.dart';
import 'package:proxydom/features/vpn/data/share_link_parser.dart';
import 'package:proxydom/features/vpn/data/subscription_device.dart';
import 'package:proxydom/features/vpn/data/subscription_label.dart';
import 'package:proxydom/features/vpn/data/subscription_traffic.dart';

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

  test('stores proxydom-profile and uses its updatedAt for traffic', () async {
    const line =
        'hysteria2://user:pass@203.0.113.12:443/?sni=c.example#Charlie';
    final header = base64Url
        .encode(utf8.encode(jsonEncode({
          'version': 1,
          'displayName': 'Терем',
          'planName': '100 GB',
          'traffic': {
            'upload': 0,
            'download': 27000000000,
            'total': 100000000000,
            'updatedAt': '2026-10-29T09:00:00Z',
          },
        })))
        .replaceAll('=', '');
    hy2HttpClientFactory = () => _StaticClient(
          status: HttpStatus.ok,
          body: line,
          headers: {'proxydom-profile': header},
        );
    final store = Hy2ImportStore.instance;
    await store.seedForTest([
      ShareCatalog(
        id: 'catalog-key',
        title: 'Старое имя',
        lines: [line],
        url: 'http://127.0.0.1/api/v1/sub/token',
      ),
    ]);

    await store.refreshCatalog('catalog-key');
    final saved = (await store.catalogs()).single;
    expect(saved.manifest, isNotNull);
    expect(saved.manifest!.displayName, 'Терем');
    expect(saved.manifest!.traffic!.total, 100000000000);
    expect(saved.trafficUpdatedAt, '2026-10-29T09:00:00.000Z');
  });

  test('a 200 base64 body replaces a 4-line catalog and its quota', () async {
    const gib = 1024 * 1024 * 1024;
    const oldMeta = 'upload=0; download=${27 * gib}; total=${100 * gib}';
    const liveHeader =
        'upload=0; download=111797992588; total=644245094400; expire=0';
    final live = parseSubscriptionTraffic(liveHeader);
    expect(live, isNotNull);
    expect(live!.expire, isNull);
    expect(formatTrafficAmount(27 * gib, russian: true), '27 ГБ');
    expect(formatTrafficAmount(100 * gib, russian: true), '100 ГБ');
    expect(formatTrafficAmount(73 * gib, russian: true), '73 ГБ');
    expect(
      formatTrafficAmount(live.upload + live.download, russian: true),
      '104 ГБ',
    );
    expect(formatTrafficAmount(live.total, russian: true), '600 ГБ');
    expect(formatTrafficAmount(live.remainingBytes, russian: true), '496 ГБ');
    expect(
      formatTrafficAmount(live.upload + live.download,
          russian: true, decimal: true),
      '112 ГБ',
    );
    expect(
      formatTrafficAmount(live.total, russian: true, decimal: true),
      '644 ГБ',
    );
    expect(decodeProfileTitle('base64:RG9EbyBWUE4='), 'DoDo VPN');

    const piped =
        'hysteria2://x:x@c.example.invalid:443/?sni=c.example.invalid#DoDoVPN | Hysteria | YouTube - x';
    expect(labelForShareLink(parseShareLink(piped)).title, isNot('YouTube'));

    const plain = '''
hysteria2://x:x@a.example.invalid:443/?sni=a.example.invalid#synth-hy2-a
hysteria2://x:x@b.example.invalid:443/?sni=b.example.invalid#synth-hy2-b
hysteria2://x:x@c.example.invalid:443/?sni=c.example.invalid#synth-hy2-c
vless://00000000-0000-0000-0000-000000000001@d.example.invalid:443#synth-vless-a
vless://00000000-0000-0000-0000-000000000002@e.example.invalid:443#synth-vless-b
''';
    final body = base64Encode(utf8.encode(plain));
    expect(body.contains('://'), isFalse);
    expect(parseShareSubscription(body), hasLength(5));
    expect(
      decideDocumentSync(status: 200, body: body),
      DocumentSyncDecision.replace,
    );

    const oldLines = [
      'hysteria2://x:x@old-a.example.invalid:443/?sni=old-a.example.invalid#YouTube',
      'hysteria2://x:x@old-b.example.invalid:443/?sni=old-b.example.invalid#США',
      'hysteria2://x:x@old-c.example.invalid:443/?sni=old-c.example.invalid#Игровой',
      'hysteria2://x:x@old-d.example.invalid:443/?sni=old-d.example.invalid#Нидерланды',
    ];
    const oldStamp = '2026-10-01T09:00:00Z';
    final sent = <Map<String, String>>[];
    hy2HttpClientFactory = () => _CapturingClient(
          sent,
          status: HttpStatus.ok,
          body: body,
          responseHeaders: {
            'subscription-userinfo': liveHeader,
            'profile-title': 'base64:${base64Encode(utf8.encode('Synth VPN'))}',
            'profile-update-interval': '1',
          },
        );
    final store = Hy2ImportStore.instance;
    await store.seedForTest([
      ShareCatalog(
        id: 'catalog-key',
        title: 'Прокси Дом',
        lines: oldLines,
        url: 'http://example.invalid/v2/synthetic',
        etag: 'W/"old-document"',
        trafficMeta: oldMeta,
        trafficUpdatedAt: oldStamp,
        lastUpdated: oldStamp,
      ),
    ]);

    final outcome = await store.refreshCatalog('catalog-key');
    final saved = (await store.catalogs()).single;
    expect(outcome.kind, ShareRefreshKind.updated);
    expect(outcome.count, 5);
    expect(sent.single['if-none-match'], isNull);
    expect(saved.title, 'Synth VPN');
    expect(saved.lines, hasLength(5));
    expect(saved.lines.join('\n'), isNot(contains('Нидерланды')));
    expect(saved.trafficMeta, liveHeader);
    expect(
      formatTrafficAmount(
        parseSubscriptionTraffic(saved.trafficMeta)!.total,
        russian: true,
      ),
      '600 ГБ',
    );
    expect(saved.updateIntervalHours, 1);
    expect(saved.lastUpdated, isNot(oldStamp));
    expect(saved.trafficUpdatedAt, isNot(oldStamp));
    expect(saved.manifest, isNull);
  });

  test('an unreadable 200 keeps the old lines and does not move the stamp',
      () async {
    const old = '2026-10-01T09:00:00Z';
    const line =
        'hysteria2://x:x@old.example.invalid:443/?sni=old.example.invalid#YouTube';
    final junk = base64Encode(utf8.encode('not a subscription document'));
    expect(
      decideDocumentSync(status: 200, body: junk),
      DocumentSyncDecision.keep,
    );
    hy2HttpClientFactory = () => _StaticClient(
          status: HttpStatus.ok,
          body: junk,
          headers: {
            'subscription-userinfo':
                'upload=0; download=111797992588; total=644245094400; expire=0',
            'profile-title': 'base64:U3ludGggVlBO',
          },
        );
    final store = Hy2ImportStore.instance;
    await store.seedForTest([
      ShareCatalog(
        id: 'catalog-key',
        title: 'Прокси Дом',
        lines: [line],
        url: 'http://example.invalid/v2/synthetic',
        trafficMeta: 'upload=0; download=1; total=10',
        trafficUpdatedAt: old,
        lastUpdated: old,
      ),
    ]);

    final outcome = await store.refreshCatalog('catalog-key');
    final saved = (await store.catalogs()).single;
    expect(outcome.kind, ShareRefreshKind.unchanged);
    expect(saved.lines, [line]);
    expect(saved.title, 'Прокси Дом');
    expect(saved.trafficMeta, 'upload=0; download=1; total=10');
    expect(saved.lastUpdated, old);
    expect(saved.trafficUpdatedAt, old);
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

class _CapturingClient extends Fake implements HttpClient {
  _CapturingClient(
    this.sent, {
    required this.status,
    required this.body,
    required this.responseHeaders,
  });

  final List<Map<String, String>> sent;
  final int status;
  final String body;
  final Map<String, String> responseHeaders;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    return _CapturingRequest(
      sent,
      status: status,
      body: body,
      responseHeaders: responseHeaders,
    );
  }

  @override
  void close({bool force = false}) {}
}

class _CapturingRequest extends Fake implements HttpClientRequest {
  _CapturingRequest(
    this.sent, {
    required this.status,
    required this.body,
    required this.responseHeaders,
  });

  final List<Map<String, String>> sent;
  final int status;
  final String body;
  final Map<String, String> responseHeaders;
  final _headers = _CapturingHeaders();

  @override
  HttpHeaders get headers => _headers;

  @override
  Future<HttpClientResponse> close() async {
    sent.add(Map<String, String>.from(_headers.values));
    return _RecordingResponse(
      status: status,
      body: body,
      headers: responseHeaders,
    );
  }
}

class _CapturingHeaders extends Fake implements HttpHeaders {
  final values = <String, String>{};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name.toLowerCase()] = '$value';
  }

  @override
  String? value(String name) => values[name.toLowerCase()];
}
