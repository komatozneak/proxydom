import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../vpn/data/vpn_controller.dart';

/// Live ↓/↑ from Android EventChannel `proxydom/vpn/traffic`.
final trafficStatsProvider = StreamProvider<VpnTrafficStats>((ref) {
  return VpnController.instance.trafficStream;
});
