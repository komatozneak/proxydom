import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../vpn/data/vpn_controller.dart';
import 'vpn_provider.dart';
import 'vpn_status.dart';

/// Live ↓/↑ from Android EventChannel `teremok/vpn/traffic`.
final trafficStatsProvider = StreamProvider<VpnTrafficStats>((ref) {
  return VpnController.instance.trafficStream;
});

/// Ping EventChannel source — overridable in tests without a platform channel.
final vpnPingStreamProvider = Provider<Stream<int?>>((ref) {
  return VpnController.instance.pingStream;
});

/// Path RTT (ms) from native VPN ping monitor via EventChannel.
///
/// Null while disconnected, until the first plausible sample, or after native
/// clears a stale sample (consecutive probe failures → `delayMs: null`).
/// Rejects are done natively (30–5000 ms). No Dart Socket/HTTP while TUN up.
///
/// Important: do **not** `ref.read`/`ref.watch` after an `await` here — when
/// [vpnProvider] flips, Riverpod rebuilds this provider and cancels the
/// subscription. Reading mid-stream caused `!_didChangeDependency` (Nest desync).
final homePingMsProvider = StreamProvider.autoDispose<int?>((ref) {
  final status = ref.watch(vpnProvider);
  if (status is! VpnConnected) {
    return Stream<int?>.value(null);
  }
  return ref.watch(vpnPingStreamProvider);
});
