import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/core/diagnostics/app_log_buffer.dart';
import 'package:proxydom/core/diagnostics/session_trace.dart';
import 'package:proxydom/core/diagnostics/tunnel_log_level.dart';

void main() {
  setUp(() {
    AppLogBuffer.instance.resetForTest();
    AppLogBuffer.instance.minLevel = TunnelLogLevel.debug;
    SessionTrace.resetForTest();
  });

  tearDown(SessionTrace.resetForTest);

  test('phase clock starts at zero and keeps the sid', () {
    SessionTrace.begin('abc');
    SessionTrace.mark('config', {'scheme': 'vless'});
    final lines = AppLogBuffer.instance.recentLines();
    expect(lines.first, contains('phase=begin'));
    expect(lines.first, contains('sid=abc'));
    final beginMs = int.parse(RegExp(r'ms=(\d+)').firstMatch(lines.first)!.group(1)!);
    expect(beginMs, lessThan(20));
    expect(lines.last, contains('phase=config'));
    expect(lines.last, contains('scheme=vless'));
  });
}
