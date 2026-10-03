import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/core/config.dart';

/// Documents Dio 5 join: `uri = baseUrl + path` (no separator).
/// Paths without a leading `/` break `/v2…` into `/v2billing…`.
void main() {
  const base = AppConfig.vpsBaseUrl;

  RequestOptions opts(String path) =>
      RequestOptions(path: path, baseUrl: base);

  test('leading-slash paths stay under /v2', () {
    expect(
      opts('/billing/subscription').uri.path,
      '/v2/billing/subscription',
    );
    expect(opts('/vpn/nodes').uri.path, '/v2/vpn/nodes');
    expect(opts('/app/version').uri.path, '/v2/app/version');
  });

  test('missing leading slash concatenates into v2 segment (regression)', () {
    expect(
      opts('billing/subscription').uri.path,
      '/v2billing/subscription',
    );
    expect(opts('app/version').uri.path, '/v2app/version');
  });
}
