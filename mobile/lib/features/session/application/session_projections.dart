import '../../account/data/account_profile.dart';
import '../../auth/data/auth_api.dart';
import '../../settings/data/subscription_status.dart';
import '../data/account_session_snapshot.dart';

/// Map session entitlement → Settings subscription model (no extra GET).
SubscriptionStatus subscriptionFromSession(AccountSessionSnapshot snap) {
  final tier = snap.tier;
  if (tier == 'free') {
    return const SubscriptionStatus();
  }
  return SubscriptionStatus(
    plan: snap.plan ?? tier,
    status: 'active',
    expiresAt: snap.endsAt,
    isPro: tier == 'pro',
    isTrial: tier == 'trial',
    isAlpha: tier == 'alpha',
    quotaUnlimited: true,
  );
}

AccountProfile profileFromSession(AccountSessionSnapshot snap) {
  return AccountProfile(
    accountId: snap.accountId,
    hasAccess: snap.hasAccess,
    devicesCount: snap.devices.length,
    deviceLimit: snap.deviceLimit,
    contactLinked: snap.telegramUsername != null,
    telegramUsername: snap.telegramUsername,
    hasRecoveryCode: snap.manageAccount,
    seatRole: snap.manageAccount ? 'owner' : 'member',
  );
}

DeviceListResult devicesFromSession(AccountSessionSnapshot snap) {
  return DeviceListResult(
    devices: [
      for (final d in snap.devices)
        DeviceSlot(
          id: d.id,
          status: 'active',
          createdAt: d.createdAt ?? DateTime.now(),
          deviceName: d.name,
          platform: d.platform,
          isCurrent: d.isCurrent,
          seatRole: d.manageAccount ? 'owner' : 'member',
          isOwner: d.manageAccount,
        ),
    ],
    activeCount: snap.devices.length,
    maxDevices: snap.deviceLimit,
  );
}
