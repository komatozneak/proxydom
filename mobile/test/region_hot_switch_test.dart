import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/features/home/application/vpn_provider.dart';
import 'package:proxydom/features/home/application/vpn_status.dart';
import 'package:proxydom/features/vpn/presentation/locations_screen.dart';

void main() {
  group('regionPickUsesBusyOverlay', () {
    test('skips busy overlay while Connected or Connecting', () {
      expect(
        regionPickUsesBusyOverlay(
          VpnConnected(
            serverName: 'Медиа',
            protocol: 'HYSTERIA2',
            connectedSince: DateTime.utc(2026, 9, 16),
          ),
        ),
        isFalse,
      );
      expect(
        regionPickUsesBusyOverlay(const VpnConnecting(progress: 0.4)),
        isFalse,
      );
    });

    test('keeps busy overlay when Disconnected or Error', () {
      expect(regionPickUsesBusyOverlay(const VpnDisconnected()), isTrue);
      expect(
        regionPickUsesBusyOverlay(const VpnError(message: 'x')),
        isTrue,
      );
    });
  });

  group('runHotRegionSwitch', () {
    test('mints before stop and connect', () async {
      final steps = <String>[];
      await runHotRegionSwitch(
        mint: () async => steps.add('mint'),
        stopAndWaitIdle: () async => steps.add('stop'),
        connectReuse: () async => steps.add('connect'),
      );
      expect(steps, ['mint', 'stop', 'connect']);
    });

    test('does not stop before mint completes', () async {
      var mintDone = false;
      var stopSawMint = false;
      await runHotRegionSwitch(
        mint: () async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          mintDone = true;
        },
        stopAndWaitIdle: () async {
          stopSawMint = mintDone;
        },
        connectReuse: () async {},
      );
      expect(stopSawMint, isTrue);
    });
  });
}
