import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/core/diagnostics/windows_service_log.dart';

void main() {
  test('debug report keeps both journals and masks a share secret', () {
    const window = 'vpn.connect_fail code=tun_init_timeout';
    const service = 'event=tun_init_timeout code=adapter_not_found '
        'hysteria2://secret+pass@cdn.example:443';
    final report = windowsDebugReport(window, service);
    expect(report, contains('=== window ==='));
    expect(report, contains('=== service ==='));
    expect(report, contains('tun_init_timeout'));
    expect(report, contains('adapter_not_found'));
    expect(report.contains('secret+pass'), isFalse);
    expect(report, contains('hysteria2://***@cdn.example:443'));
  });
}