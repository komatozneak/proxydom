import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ios_store_gates.dart';
import '../../vpn/data/vpn_controller.dart';
import '../../vpn/data/windows_ping_probe.dart';
import 'vpn_provider.dart';
import 'vpn_status.dart';

/// The side-effecting probe is injectable so widget tests do not open sockets.
final windowsPingSourceProvider = Provider<Stream<int?> Function()>((ref) {
  return () => windowsPingStream();
});

/// Native Home ping from EventChannel `proxydom/vpn/ping`.
///
/// Injectable for the same reason: a widget test reads a scripted stream
/// instead of opening the platform channel.
final vpnPingStreamProvider = Provider<Stream<int?>>((ref) {
  return VpnController.instance.pingStream;
});

/// Where Home shows a measured tunnel RTT.
///
/// Windows measures it in this process: Runner's sockets cross the same TUN
/// and engine as any other application. Android already runs one SOCKS CONNECT
/// every five seconds for path health and pushes that RTT over the channel, so
/// the number costs no extra connection. iOS has only a stub channel, so it
/// shows no ping at all rather than a dash.
bool get homePingSupported {
  if (kIsWeb) return false;
  return windowsDesktop || defaultTargetPlatform == TargetPlatform.android;
}

/// Application-level tunnel RTT for the compact Home metric.
///
/// Null while disconnected, until the first plausible sample, or after the
/// native side cleared a stale one. Home reads null as "no reading yet" and
/// prints an ellipsis, never `0`: zero is not a measured RTT.
final pingDelayMsProvider = StreamProvider.autoDispose<int?>((ref) {
  final status = ref.watch(vpnProvider);
  if (status is! VpnConnected) return Stream<int?>.value(null);
  if (windowsDesktop) return ref.watch(windowsPingSourceProvider)();
  if (!homePingSupported) return Stream<int?>.value(null);
  return ref.watch(vpnPingStreamProvider);
});
