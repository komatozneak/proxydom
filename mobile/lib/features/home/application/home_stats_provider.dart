import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../vpn/data/vpn_controller.dart';
import 'vpn_provider.dart';
import 'vpn_status.dart';

/// Live ↓/↑ from Android EventChannel `teremok/vpn/traffic`.
final trafficStatsProvider = StreamProvider<VpnTrafficStats>((ref) {
  return VpnController.instance.trafficStream;
});

/// Path RTT (ms) from libbox `CommandClient.urlTest` via EventChannel.
///
/// Null while disconnected or until the first plausible sample arrives.
/// Rejects are done natively (30–5000 ms). No Dart Socket/HTTP while TUN up.
final homePingMsProvider = StreamProvider.autoDispose<int?>((ref) async* {
  final status = ref.watch(vpnProvider);
  if (status is! VpnConnected) {
    yield null;
    return;
  }

  yield null;
  await for (final ms in VpnController.instance.pingStream) {
    if (ref.read(vpnProvider) is! VpnConnected) {
      yield null;
      return;
    }
    yield ms;
  }
});
