import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/core/diagnostics/app_log_buffer.dart';
import 'package:teremok_connect/core/diagnostics/session_trace.dart';
import 'package:teremok_connect/core/diagnostics/tunnel_log_level.dart';

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
    expect(lines.first, contains('ms=0'));
    expect(lines.last, contains('phase=config'));
    expect(lines.last, contains('scheme=vless'));
  });
}
