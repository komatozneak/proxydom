import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/core/diagnostics/tunnel_log_badge.dart';

void main() {
  test('badge is only the level token', () {
    const line = '2026-09-25T08:00:00.000Z [error] [vpn] vpn.phase phase=fail';
    final badge = tunnelLogBadge(line);
    expect(badge, isNotNull);
    expect(badge!.label, 'error');
    expect(badge.before, '2026-09-25T08:00:00.000Z ');
    expect(badge.after, ' [vpn] vpn.phase phase=fail');
  });

  test('warning token folds to warn', () {
    final badge = tunnelLogBadge('[Warning] core.xray started');
    expect(badge!.label, 'warn');
    expect(badge.after, ' core.xray started');
  });

  test('a line without a level stays whole', () {
    expect(tunnelLogBadge('vpn.phase phase=begin'), isNull);
  });
}
