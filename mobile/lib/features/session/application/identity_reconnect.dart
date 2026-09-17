import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../home/application/vpn_provider.dart';

/// After accept / leave / revoke the HMAC and VPN creds rotated — drop the tunnel.
Future<void> teardownVpnAfterIdentityChange(WidgetRef ref) async {
  try {
    // Rotated creds make the persisted native session stale — stop and wipe
    // in one native operation so no old identity can be resurrected.
    await ref.read(vpnProvider.notifier).disconnect(
          reason: 'identity_change',
          wipeNativeSession: true,
        );
  } catch (_) {}
  try {
    await ref.read(vpnNodesRepositoryProvider).refreshAfterEntitlementChange();
  } catch (_) {}
}

/// Restore/link must not start a connect walk. Auto shade-Connected would
/// paint Nest as connected while native is still Idle (revoked guest keys).
bool shouldAutoConnectAfterIdentityChange() => false;

/// Telegram restore rotates account creds — drop the old tunnel and stay
/// Disconnected. The user taps Nest when they want a new session.
Future<void> reconnectVpnAfterIdentityChange(WidgetRef ref) async {
  final vpn = ref.read(vpnProvider.notifier);
  vpn.suppressAutoReconnect();
  await teardownVpnAfterIdentityChange(ref);
  try {
    await vpn.waitUntilNativeIdle();
  } catch (_) {}
}
