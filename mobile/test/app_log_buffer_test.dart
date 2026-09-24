import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/core/diagnostics/app_log_buffer.dart';
import 'package:teremok_connect/core/diagnostics/product_log.dart';
import 'package:teremok_connect/core/diagnostics/tunnel_log_level.dart';

void main() {
  tearDown(AppLogBuffer.instance.resetForTest);

  test('AppLogBuffer drops lines above the selected level', () {
    final buf = AppLogBuffer.instance;
    buf.clear();
    buf.minLevel = TunnelLogLevel.off;
    buf.info('hidden');
    expect(buf.recentLines(), isEmpty);
    buf.minLevel = TunnelLogLevel.error;
    buf.info('still hidden');
    buf.error('kept');
    final text = buf.formatRecentLog();
    expect(text, contains('[error] kept'));
    expect(text, isNot(contains('still hidden')));
    expect(text, isNot(contains('hidden')));
  });

  test('info level hides boot noise and keeps session lines', () {
    final buf = AppLogBuffer.instance;
    buf.clear();
    buf.minLevel = TunnelLogLevel.info;
    buf.debug('app.boot t0');
    buf.debug('api.discovery cached_origin=https://api.example');
    buf.info('vpn.native status=idle');
    buf.info('vpn.connect_fail code=egressTimeout');
    buf.info('vpn.native status=connected');
    final text = buf.formatRecentLog();
    expect(text, isNot(contains('app.boot')));
    expect(text, isNot(contains('api.discovery')));
    expect(text, contains('vpn.connect_fail code=egressTimeout'));
    expect(text, contains('vpn.native status=connected'));
  });

  test('AppLogBuffer keeps last N lines', () {
    final buf = AppLogBuffer.instance;
    buf.clear();
    for (var i = 0; i < 900; i++) {
      buf.info('line $i');
    }
    final lines = buf.recentLines();
    expect(lines.length, AppLogBuffer.maxLines);
    expect(lines.first, contains('line 100'));
    expect(lines.last, contains('line 899'));
  });

  test('AppLogBuffer persists across attach', () async {
    final file = File(
      '${Directory.systemTemp.path}/teremok_product_log_test.log',
    );
    if (await file.exists()) {
      await file.delete();
    }
    final buf = AppLogBuffer.instance;
    await buf.attachPersistFile(file);
    buf.info('vpn.connected winner_id=us-geo-1');
    await buf.flushPersist();

    buf.resetForTest();
    await buf.attachPersistFile(file);
    expect(buf.formatRecentLog(), contains('vpn.connected winner_id=us-geo-1'));
    await file.delete();
  });

  test('ProductLog writes structured events without PII keys', () {
    final buf = AppLogBuffer.instance;
    buf.clear();
    ProductLog.event('vpn.mint', {
      'id': 'us-geo-1',
      'active_core': 'xray',
      'skip': null,
    });
    final text = buf.formatRecentLog();
    expect(text, contains('vpn.mint id=us-geo-1 active_core=xray'));
    expect(text, isNot(contains('skip=')));
  });

  test('ProductLog vpn.egress_probe keeps catalog IPv4 not SNI', () {
    final buf = AppLogBuffer.instance;
    buf.clear();
    ProductLog.event('vpn.egress_probe', {
      'external_ip': '217.60.3.9',
      'winner_id': 'eu-hy2-1',
      'catalog_host': '217.60.3.9',
    });
    final text = buf.formatRecentLog();
    expect(
      text,
      contains(
        'vpn.egress_probe external_ip=217.60.3.9 '
        'winner_id=eu-hy2-1 catalog_host=217.60.3.9',
      ),
    );
    expect(text, isNot(contains('hy2-eu.teremokconnect.online')));
  });
}
