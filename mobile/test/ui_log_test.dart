import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/core/diagnostics/app_log_buffer.dart';
import 'package:proxydom/core/diagnostics/tunnel_log_level.dart';
import 'package:proxydom/core/diagnostics/product_log.dart';
import 'package:proxydom/core/diagnostics/ui_log.dart';

void main() {
  setUp(() {
    AppLogBuffer.instance.resetForTest();
    AppLogBuffer.instance.minLevel = TunnelLogLevel.debug;
  });

  test('ignored tap records the reason and drops empty fields', () {
    UiLog.action(
      'home',
      'nest',
      result: 'ignored',
      reason: 'busy',
    );
    final line = AppLogBuffer.instance.recentLines().single;
    expect(line, contains('[debug] [ui] ui.action'));
    expect(line, contains('screen=home'));
    expect(line, contains('action=nest'));
    expect(line, contains('result=ignored'));
    expect(line, contains('reason=busy'));
  });

  test('a rejected house tap is a warning', () {
    UiLog.action(
      'home',
      'nest',
      level: ProductLogLevel.warn,
      result: 'rejected',
      reason: 'already_connecting',
    );
    final line = AppLogBuffer.instance.recentLines().single;
    expect(line, contains('[warn] [ui]'));
    expect(line, contains('result=rejected'));
  });
}
