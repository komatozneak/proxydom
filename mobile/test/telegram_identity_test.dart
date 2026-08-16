import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/features/account/application/telegram_identity.dart';
import 'package:teremok_connect/features/home/application/vpn_status.dart';

void main() {
  test('telegram identity is offered only while VPN is connected', () {
    expect(telegramIdentityAllowed(const VpnDisconnected()), isFalse);
    expect(telegramIdentityAllowed(const VpnConnecting(progress: 0.2)), isFalse);
    expect(
      telegramIdentityAllowed(const VpnError(message: 'x')),
      isFalse,
    );
    expect(
      telegramIdentityAllowed(
        VpnConnected(
          serverName: 'EU',
          protocol: 'hy2',
          connectedSince: DateTime.utc(2026, 8, 16),
        ),
      ),
      isTrue,
    );
  });
}
