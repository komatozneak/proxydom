import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/core/config.dart';

/// Documents Dio 5 join: `uri = baseUrl + path` (no separator).
/// Paths without a leading `/` break `/api/v1…` into `/api/v1billing…`.
void main() {
  const base = AppConfig.vpsBaseUrl;

  RequestOptions opts(String path) =>
      RequestOptions(path: path, baseUrl: base);

  test('leading-slash paths stay under /api/v1', () {
    expect(
      opts('/billing/subscription').uri.path,
      '/api/v1/billing/subscription',
    );
    expect(opts('/vpn/nodes').uri.path, '/api/v1/vpn/nodes');
    expect(opts('/app/version').uri.path, '/api/v1/app/version');
  });

  test('missing leading slash concatenates into v1 segment (regression)', () {
    expect(
      opts('billing/subscription').uri.path,
      '/api/v1billing/subscription',
    );
    expect(opts('app/version').uri.path, '/api/v1app/version');
  });
}
