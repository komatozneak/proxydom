import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/core/diagnostics/tunnel_log_format.dart';

void main() {
  test('iso and epoch-millis lines share one clock', () {
    const dart = '2026-09-25T10:22:44.023Z [info] [doc] doc.fetch';
    const raw = '1790331025062 DefaultNetworkMonitor net.iface rmnet1';
    final dartTime = tunnelLogTime(dart);
    final later = tunnelLogTime('2026-09-25T10:22:57.031Z [info] [hy2] hy2.socks');
    expect(dartTime, isNotNull);
    expect(later, isNotNull);
    expect(dartTime!.isBefore(later!), isTrue);
    expect(tunnelLogSource('doc.fetch host=api.example'), 'doc');
    expect(tunnelLogSource('hy2.socks action=start'), 'hy2');
    final older = tunnelLogTime('2026-09-25T10:10:25.000Z [debug] [net] net.iface');
    final epoch = tunnelLogTime(raw);
    final newer = tunnelLogTime('2026-09-25T10:10:25.100Z [info] [ui] ui.action');
    expect(epoch, DateTime.utc(2026, 9, 25, 10, 10, 25, 62));
    expect(older!.isBefore(epoch!), isTrue);
    expect(epoch.isBefore(newer!), isTrue);
  });
}
