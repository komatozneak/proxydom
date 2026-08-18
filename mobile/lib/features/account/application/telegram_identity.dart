import '../../../l10n/app_localizations.dart';
import '../../home/application/vpn_status.dart';

/// Telegram is blocked in RF without a tunnel — only offer TG identity
/// after Teremok VPN is connected.
bool telegramIdentityAllowed(VpnStatus status) => status is VpnConnected;

enum TelegramPollStatus {
  pending,
  needsDeviceSlot,
  linked,
  confirmed,
  failed,
  expired,
  unknown,
}

enum TelegramPollError {
  memberSlotRevoked,
  subscriptionInactive,
  other,
}

/// Typed view over the contact API's JSON polling contract.
class TelegramPollOutcome {
  const TelegramPollOutcome({
    required this.status,
    required this.error,
    required this.data,
  });

  factory TelegramPollOutcome.fromJson(Map<String, dynamic> data) {
    final status = switch (data['status']) {
      'pending' => TelegramPollStatus.pending,
      'needs_device_slot' => TelegramPollStatus.needsDeviceSlot,
      'linked' => TelegramPollStatus.linked,
      'confirmed' => TelegramPollStatus.confirmed,
      'failed' => TelegramPollStatus.failed,
      'expired' => TelegramPollStatus.expired,
      _ => TelegramPollStatus.unknown,
    };
    final error = switch (data['error']) {
      'member_slot_revoked' => TelegramPollError.memberSlotRevoked,
      'subscription_inactive' => TelegramPollError.subscriptionInactive,
      _ => TelegramPollError.other,
    };
    return TelegramPollOutcome(status: status, error: error, data: data);
  }

  final TelegramPollStatus status;
  final TelegramPollError error;
  final Map<String, dynamic> data;

  bool get isAccountRestore {
    if (status != TelegramPollStatus.confirmed) return false;
    final access = data['access_token'];
    return access is String && access.isNotEmpty;
  }
}

/// Cross-install restore: poll `confirmed` with JWT. `linked` is same-account bind.
bool telegramPollIsAccountRestore(Map<String, dynamic> poll) =>
    TelegramPollOutcome.fromJson(poll).isAccountRestore;

bool telegramRestoreIsMember(Map<String, dynamic> data) {
  final session = data['session'];
  if (session is! Map) return false;
  final device = session['device'];
  if (device is! Map) return false;
  final caps = device['caps'];
  if (caps is! List) return false;
  return !caps.any((cap) => cap.toString() == 'manage_account');
}

/// User-facing copy for Telegram poll `failed` error codes (ADR 019).
String telegramPollErrorMessage(AppL10n l, Object? error) {
  final typed = switch (error?.toString()) {
    'member_slot_revoked' => TelegramPollError.memberSlotRevoked,
    'subscription_inactive' => TelegramPollError.subscriptionInactive,
    _ => TelegramPollError.other,
  };
  return telegramPollErrorCopy(l, typed);
}

String telegramPollErrorCopy(AppL10n l, TelegramPollError error) =>
    switch (error) {
      TelegramPollError.memberSlotRevoked => l.restoreTelegramSlotRevoked,
      TelegramPollError.subscriptionInactive =>
        l.restoreTelegramSubscriptionInactive,
      TelegramPollError.other => l.restoreFailed,
    };

String telegramSuccessTitle(
  AppL10n l, {
  required bool restored,
  required bool member,
  required String handle,
}) {
  if (member) return l.accountTelegramMemberRestoredTitle;
  if (restored) return l.accountTelegramOwnerRestoredTitle;
  return l.accountTelegramLinkedTitle(handle);
}

String telegramSuccessBody(
  AppL10n l, {
  required bool restored,
  required bool member,
}) {
  if (member) return l.accountTelegramMemberRestoredBody;
  if (restored) return l.accountTelegramOwnerRestoredBody;
  return l.accountTelegramLinkedBody;
}
