import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/features/auth/application/auth_provider.dart';
import 'package:teremok_connect/features/auth/application/auth_state.dart';
import 'package:teremok_connect/features/session/application/session_provider.dart';
import 'package:teremok_connect/features/session/data/account_session_snapshot.dart';
import 'package:teremok_connect/features/settings/application/subscription_status_provider.dart';
import 'package:teremok_connect/features/settings/data/subscription_status.dart';

const _freeQuota = SubscriptionStatus(
  quotaBytesLimit: 1 << 32,
  quotaBytesRemaining: 1 << 31,
  quotaBytesUsed: 1 << 31,
);

class _AuthedNotifier extends AuthNotifier {
  @override
  Future<AuthState> build() async => const AuthStateAuthenticated(
        accessToken: 'test-access',
        refreshToken: 'test-refresh',
      );
}

class _FreeSessionNotifier extends SessionNotifier {
  _FreeSessionNotifier();

  int _version = 1;
  int refreshCalls = 0;

  AccountSessionSnapshot _snap() => AccountSessionSnapshot(
        version: _version,
        accountId: 1,
        tier: 'free',
        hasAccess: true,
        deviceLimit: 1,
        devices: const [],
      );

  @override
  Future<AccountSessionSnapshot?> build() async => _snap();

  @override
  Future<void> refresh() async {
    refreshCalls++;
    fail('session refresh must not run from subscription refresh');
  }

  void bumpVersion() {
    _version++;
    state = AsyncData(_snap());
  }
}

class _SlowFreeNotifier extends SubscriptionStatusNotifier {
  Completer<SubscriptionStatus>? hold;
  var fetchCount = 0;

  @override
  Future<SubscriptionStatus> loadFreeQuota() async {
    fetchCount++;
    final pending = hold;
    if (pending != null) return pending.future;
    return _freeQuota;
  }
}

void main() {
  test('Free refresh does not invalidate itself when session bumps', () async {
    final session = _FreeSessionNotifier();
    final sub = _SlowFreeNotifier();
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(_AuthedNotifier.new),
        sessionProvider.overrideWith(() => session),
        subscriptionStatusProvider.overrideWith(() => sub),
      ],
    );
    addTearDown(container.dispose);
    container.listen(subscriptionStatusProvider, (_, __) {}, fireImmediately: true);

    await container.read(subscriptionStatusProvider.future);
    expect(container.read(subscriptionStatusProvider).hasValue, isTrue);
    expect(session.refreshCalls, 0);

    sub.hold = Completer<SubscriptionStatus>();
    final refresh = container.read(subscriptionStatusProvider.notifier).refresh();
    session.bumpVersion();
    sub.hold!.complete(_freeQuota);
    await refresh;

    expect(container.read(subscriptionStatusProvider).hasError, isFalse);
    expect(container.read(subscriptionStatusProvider).asData?.value.quotaBytesLimit,
        _freeQuota.quotaBytesLimit);
    expect(session.refreshCalls, 0);
  });

  test('Free refresh keeps previous data instead of AsyncLoading', () async {
    final session = _FreeSessionNotifier();
    final sub = _SlowFreeNotifier();
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(_AuthedNotifier.new),
        sessionProvider.overrideWith(() => session),
        subscriptionStatusProvider.overrideWith(() => sub),
      ],
    );
    addTearDown(container.dispose);
    container.listen(subscriptionStatusProvider, (_, __) {}, fireImmediately: true);

    await container.read(subscriptionStatusProvider.future);
    sub.hold = Completer<SubscriptionStatus>();
    final refresh = container.read(subscriptionStatusProvider.notifier).refresh();

    final mid = container.read(subscriptionStatusProvider);
    expect(mid, isA<AsyncData<SubscriptionStatus>>());
    expect(mid.asData?.value.quotaBytesLimit, _freeQuota.quotaBytesLimit);

    sub.hold!.complete(_freeQuota);
    await refresh;
  });
}
