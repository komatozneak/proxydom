import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/features/vpn/data/vpn_session_snapshot.dart';

void main() {
  test('an unread exit address does not stop the session', () {
    final unread = decideEgressProbe(null);
    expect(unread.stopSession, isFalse);
    expect(unread.result, 'egress_unknown');
    final blank = decideEgressProbe('  ');
    expect(blank.stopSession, isFalse);
    expect(blank.result, 'egress_unknown');
    final read = decideEgressProbe('194.48.250.199');
    expect(read.stopSession, isFalse);
    expect(read.result, 'ok');
  });
}
