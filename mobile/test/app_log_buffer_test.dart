import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/core/diagnostics/app_log_buffer.dart';

void main() {
  test('AppLogBuffer keeps last N lines', () {
    final buf = AppLogBuffer.instance;
    buf.clear();
    for (var i = 0; i < 250; i++) {
      buf.info('line $i');
    }
    final lines = buf.recentLines();
    expect(lines.length, 200);
    expect(lines.first, contains('line 50'));
    expect(lines.last, contains('line 249'));
  });
}
