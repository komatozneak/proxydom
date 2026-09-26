import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/core/diagnostics/app_log_buffer.dart';
import 'package:teremok_connect/core/diagnostics/tunnel_log_level.dart';
import 'package:teremok_connect/core/diagnostics/product_log.dart';
import 'package:teremok_connect/features/vpn/data/document_fetch_log.dart';

void main() {
  setUp(() {
    AppLogBuffer.instance.resetForTest();
    AppLogBuffer.instance.minLevel = TunnelLogLevel.debug;
  });

  test('fetch log keeps the host and drops the document path', () {
    logDocumentFetch(
      url: 'http://203.0.113.5:8080/sub/secret-token',
      elapsedMs: 2,
      decision: 'keep',
      error: 'SocketException',
      detail: Exception('CLEARTEXT http://203.0.113.5:8080/sub/secret-token'),
    );
    final line = AppLogBuffer.instance.recentLines().single;
    expect(line, contains('[warn] [doc] doc.fetch'));
    expect(line, contains('host=203.0.***.***'));
    expect(line, contains('port=8080'));
    expect(line, contains('error=SocketException'));
    expect(line, contains('ms=2'));
    expect(line.contains('203.0.113.5'), isFalse);
    expect(line.contains('secret-token'), isFalse);
    expect(line, contains('(url)'));
  });

  test('an empty document is a warning and a filled replace is info', () {
    expect(
      documentFetchLevel(decision: 'drop', links: 0, status: 200),
      ProductLogLevel.warn,
    );
    expect(
      documentFetchLevel(decision: 'keep', status: 304, localLinks: 0),
      ProductLogLevel.warn,
    );
    expect(
      documentFetchLevel(
        decision: 'keep',
        status: 304,
        localLinks: 4,
        links: 4,
      ),
      ProductLogLevel.info,
    );
    expect(
      documentFetchLevel(decision: 'replace', status: 200, links: 4),
      ProductLogLevel.info,
    );
  });
}
