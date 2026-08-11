/// Account hub profile from GET /me (or /v2/app/me).
class AccountProfile {
  const AccountProfile({
    required this.accountId,
    required this.hasAccess,
    required this.devicesCount,
    required this.deviceLimit,
    required this.contactLinked,
    required this.hasRecoveryCode,
    this.phone,
    this.clientId,
    this.telegramUsername,
    this.emailMasked,
  });

  final int accountId;
  final String? phone;
  final bool hasAccess;
  final int devicesCount;
  final int deviceLimit;
  final String? clientId;
  final bool contactLinked;
  final String? telegramUsername;
  final String? emailMasked;
  final bool hasRecoveryCode;

  factory AccountProfile.fromJson(Map<String, dynamic> json) {
    return AccountProfile(
      accountId: (json['account_id'] as num).toInt(),
      phone: json['phone'] as String?,
      hasAccess: json['has_access'] as bool? ?? false,
      devicesCount: (json['devices_count'] as num?)?.toInt() ?? 0,
      deviceLimit: (json['device_limit'] as num?)?.toInt() ?? 1,
      clientId: json['client_id'] as String?,
      contactLinked: json['contact_linked'] as bool? ?? false,
      telegramUsername: json['telegram_username'] as String?,
      emailMasked: json['email_masked'] as String?,
      hasRecoveryCode: json['has_recovery_code'] as bool? ?? false,
    );
  }
}
