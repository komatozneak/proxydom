import 'package:flutter_test/flutter_test.dart';

import 'package:teremok_connect/features/session/application/session_provider.dart';
import 'package:teremok_connect/features/session/data/account_session_snapshot.dart';

void main() {
  Map<String, dynamic> sessionJson(
      {required int version, required String tier}) {
    return {
      'version': version,
      'account': {
        'id': 1,
        'plan': tier == 'free' ? 'free' : 'alpha',
        'device_limit': tier == 'free' ? 1 : 5,
        'entitlement': {
          'tier': tier,
          'has_access': tier != 'free',
        },
      },
      'device': {
        'id': 10,
        'install_id': 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
        'caps': ['manage_account', 'revoke_self'],
        'is_current': true,
      },
      'devices': [
        {
          'id': 10,
          'install_id': 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
          'caps': ['manage_account', 'revoke_self'],
          'is_current': true,
          'name': 'Pixel',
          'created_at': '2026-08-15T00:00:00Z',
        },
      ],
    };
  }

  test('parses session without seat_role', () {
    final snap =
        AccountSessionSnapshot.fromJson(sessionJson(version: 2, tier: 'alpha'));
    expect(snap.version, 2);
    expect(snap.tier, 'alpha');
    expect(snap.hasAccess, isTrue);
    expect(snap.deviceLimit, 5);
    expect(snap.manageAccount, isTrue);
    expect(snap.devices.single.isCurrent, isTrue);
  });

  test('older session version is discarded by monotonic apply', () {
    final older =
        AccountSessionSnapshot.fromJson(sessionJson(version: 1, tier: 'free'));
    final newer =
        AccountSessionSnapshot.fromJson(sessionJson(version: 3, tier: 'alpha'));
    expect(sessionShouldApply(older.version, newer.version), isFalse);
    expect(sessionShouldApply(newer.version, older.version), isTrue);
    expect(sessionShouldApply(3, 3), isFalse);
    expect(sessionShouldApply(1, null), isTrue);
  });

  test('member restore session has access without manage_account', () {
    final snap = AccountSessionSnapshot.fromJson({
      'version': 4,
      'account': {
        'id': 7,
        'plan': 'alpha',
        'telegram_username': 'misha',
        'device_limit': 5,
        'entitlement': {
          'tier': 'alpha',
          'has_access': true,
        },
      },
      'device': {
        'id': 22,
        'install_id': 'bbbbbbbb-bbbb-4ccc-8ddd-eeeeeeeeeeee',
        'caps': ['revoke_self'],
        'is_current': true,
      },
      'devices': [
        {
          'id': 11,
          'install_id': 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
          'caps': ['manage_account', 'revoke_self'],
          'is_current': false,
        },
        {
          'id': 22,
          'install_id': 'bbbbbbbb-bbbb-4ccc-8ddd-eeeeeeeeeeee',
          'caps': ['revoke_self'],
          'is_current': true,
        },
      ],
    });
    expect(snap.hasAccess, isTrue);
    expect(snap.manageAccount, isFalse);
    expect(snap.telegramUsername, 'misha');
    expect(snap.currentCaps, ['revoke_self']);
  });
}
