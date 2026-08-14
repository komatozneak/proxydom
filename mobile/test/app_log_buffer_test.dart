import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/core/diagnostics/app_log_buffer.dart';
import 'package:teremok_connect/core/diagnostics/product_log.dart';

void main() {
  tearDown(AppLogBuffer.instance.resetForTest);

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
}
