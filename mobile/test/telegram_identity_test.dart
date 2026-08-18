import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/features/account/application/telegram_identity.dart';
import 'package:teremok_connect/features/home/application/vpn_status.dart';
import 'package:teremok_connect/l10n/app_localizations.dart';

void main() {
  test('telegram identity is offered only while VPN is connected', () {
    expect(telegramIdentityAllowed(const VpnDisconnected()), isFalse);
    expect(
        telegramIdentityAllowed(const VpnConnecting(progress: 0.2)), isFalse);
    expect(
      telegramIdentityAllowed(const VpnError(message: 'x')),
      isFalse,
    );
    expect(
      telegramIdentityAllowed(
        VpnConnected(
          serverName: 'EU',
          protocol: 'hy2',
          connectedSince: DateTime.utc(2026, 8, 16),
        ),
      ),
      isTrue,
    );
  });

  test('linked poll without tokens is not a cross-account restore', () {
    expect(
      TelegramPollOutcome.fromJson({'status': 'linked'}).status,
      TelegramPollStatus.linked,
    );
    expect(
      telegramPollIsAccountRestore({'status': 'linked'}),
      isFalse,
    );
    expect(
      telegramPollIsAccountRestore({
        'status': 'confirmed',
      }),
      isFalse,
    );
    expect(
      telegramPollIsAccountRestore({
        'status': 'confirmed',
        'access_token': '',
      }),
      isFalse,
    );
    expect(
      telegramPollIsAccountRestore({
        'status': 'confirmed',
        'access_token': 'jwt',
        'session': {'version': 1},
      }),
      isTrue,
    );
    expect(
      telegramRestoreIsMember({
        'session': {
          'device': {
            'caps': ['revoke_self'],
          },
        },
      }),
      isTrue,
    );
    expect(
      telegramRestoreIsMember({
        'session': {
          'device': {
            'caps': ['manage_account', 'revoke_self'],
          },
        },
      }),
      isFalse,
    );
  });

  test('telegram poll error codes map to restored/removed/inactive copy', () {
    final ru = lookupAppL10n(const Locale('ru'));
    expect(
      telegramPollErrorMessage(ru, 'member_slot_revoked'),
      ru.restoreTelegramSlotRevoked,
    );
    expect(
      telegramPollErrorMessage(ru, 'subscription_inactive'),
      ru.restoreTelegramSubscriptionInactive,
    );
    expect(telegramPollErrorMessage(ru, 'token_expired'), ru.restoreFailed);
    expect(ru.accountTelegramMemberRestoredBody, isNot(contains('управлять')));
    expect(
      ru.accountTelegramLinkedBody,
      isNot(contains('управлять подпиской')),
    );
    expect(
      telegramSuccessTitle(
        ru,
        restored: false,
        member: false,
        handle: '@misha',
      ),
      '@misha привязан',
    );
    expect(
      telegramSuccessTitle(
        ru,
        restored: true,
        member: false,
        handle: '@misha',
      ),
      'Аккаунт восстановлен',
    );
    expect(
      telegramSuccessTitle(
        ru,
        restored: true,
        member: true,
        handle: '@misha',
      ),
      'Вернулись в подписку',
    );
    expect(
      telegramSuccessBody(ru, restored: true, member: true),
      ru.accountTelegramMemberRestoredBody,
    );
    expect(
      telegramSuccessBody(ru, restored: true, member: false),
      ru.accountTelegramOwnerRestoredBody,
    );
  });
}
