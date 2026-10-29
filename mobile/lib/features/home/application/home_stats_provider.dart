import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ios_store_gates.dart';
import '../../vpn/data/vpn_controller.dart';
import '../../vpn/data/windows_ping_probe.dart';
import 'vpn_provider.dart';
import 'vpn_status.dart';

/// Live ↓/↑ from Android EventChannel `proxydom/vpn/traffic`.
final trafficStatsProvider = StreamProvider<VpnTrafficStats>((ref) {
  return VpnController.instance.trafficStream;
});

/// The side-effecting probe is injectable so widget tests do not open sockets.
final windowsPingSourceProvider = Provider<Stream<int?> Function()>((ref) {
  return () => windowsPingStream();
});

/// Application-level tunnel RTT for the compact Home metric.
///
/// Windows measures it in this process: Runner's sockets cross the same TUN
/// and engine as any other application. Mobile platforms still use their own
/// native probe, so they keep the placeholder until that integration lands.
final pingDelayMsProvider = StreamProvider.autoDispose<int?>((ref) {
  final status = ref.watch(vpnProvider);
  if (!windowsDesktop || status is! VpnConnected) {
    return Stream<int?>.value(null);
  }
  return ref.watch(windowsPingSourceProvider)();
});
