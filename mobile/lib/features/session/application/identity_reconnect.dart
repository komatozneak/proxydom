import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../home/application/vpn_provider.dart';

/// After accept / leave / revoke the HMAC and VPN creds rotated — drop the tunnel.
Future<void> teardownVpnAfterIdentityChange(WidgetRef ref) async {
  try {
    await ref.read(vpnProvider.notifier).disconnect();
  } catch (_) {}
  try {
    await ref.read(vpnNodesRepositoryProvider).refreshAfterEntitlementChange();
  } catch (_) {}
}

/// Telegram restore rotates account creds — fetch a new config and come back up.
Future<void> reconnectVpnAfterIdentityChange(WidgetRef ref) async {
  await teardownVpnAfterIdentityChange(ref);
  try {
    await ref.read(vpnProvider.notifier).connect();
  } catch (_) {}
}
