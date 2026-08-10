import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/features/home/application/home_stats_provider.dart';
import 'package:teremok_connect/features/home/application/vpn_provider.dart';
import 'package:teremok_connect/features/home/application/vpn_status.dart';

class _MutableVpnNotifier extends VpnNotifier {
  _MutableVpnNotifier(this._status);

  VpnStatus _status;

  @override
  VpnStatus build() => _status;

  void setStatus(VpnStatus next) {
    _status = next;
    state = next;
  }
}

void main() {
  test(
    'homePingMsProvider yields null after disconnect without Riverpod assertion',
    () async {
      final ping = StreamController<int?>.broadcast();
      addTearDown(ping.close);

      final vpn = _MutableVpnNotifier(
        VpnConnected(
          serverName: 'EU',
          protocol: 'VLESS',
          connectedSince: DateTime(2026, 1, 1),
        ),
      );

      final container = ProviderContainer(
        overrides: [
          vpnProvider.overrideWith(() => vpn),
          vpnPingStreamProvider.overrideWithValue(ping.stream),
        ],
      );
      addTearDown(container.dispose);

      final values = <AsyncValue<int?>>[];
      final sub = container.listen(
        homePingMsProvider,
        (_, next) => values.add(next),
        fireImmediately: true,
      );
      addTearDown(sub.close);

      await pumpEventQueue();
      ping.add(42);
      await pumpEventQueue();

      expect(
        container.read(homePingMsProvider).asData?.value,
        42,
      );

      // Flip dependency while the ping stream is still open — must not throw
      // `!_didChangeDependency` (old async* + ref.read after await).
      expect(
        () => vpn.setStatus(const VpnDisconnected()),
        returnsNormally,
      );
      await pumpEventQueue();

      expect(container.read(homePingMsProvider).asData?.value, isNull);

      // Further pings after disconnect must not poison the provider.
      ping.add(99);
      await pumpEventQueue();
      expect(container.read(homePingMsProvider).asData?.value, isNull);
    },
  );

  test('homePingMsProvider is null while disconnected', () async {
    final container = ProviderContainer(
      overrides: [
        vpnProvider.overrideWith(
          () => _MutableVpnNotifier(const VpnDisconnected()),
        ),
        vpnPingStreamProvider.overrideWithValue(
          Stream<int?>.periodic(
            const Duration(milliseconds: 10),
            (_) => 1,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final sub = container.listen(homePingMsProvider, (_, __) {});
    addTearDown(sub.close);
    await pumpEventQueue();

    expect(container.read(homePingMsProvider).asData?.value, isNull);
  });
}
