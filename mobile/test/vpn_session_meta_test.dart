import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teremok_connect/features/vpn/data/vpn_session_meta.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('mint must not overwrite winner expected host', () async {
    await VpnSessionMeta.saveConnectMeta(
      expectedEgressHost: '217.60.3.9',
      winnerNodeId: 'eu-hy2-1',
      displayLabel: 'Латвия',
      protocol: 'hysteria2',
    );
    await VpnSessionMeta.saveConnectMeta(
      ruRulesLoaded: true,
      ruRuleTags: const [],
      updateExpectedHost: false,
    );
    final meta = await VpnSessionMeta.load();
    expect(meta.expectedEgressHost, '217.60.3.9');
    expect(meta.winnerNodeId, 'eu-hy2-1');
    expect(meta.displayLabel, 'Латвия');
    expect(meta.protocol, 'hysteria2');
    expect(meta.ruRulesLoaded, isTrue);
  });
}
