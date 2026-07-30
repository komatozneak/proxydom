import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teremok_connect/features/beta/application/post_auth_router.dart';
import 'package:teremok_connect/features/beta/data/beta_entitlement.dart';
import 'package:teremok_connect/features/beta/data/beta_usage_aggregate_store.dart';
import 'package:teremok_connect/features/onboarding/data/onboarding_prefs.dart';

void main() {
  group('PostAuthRouter', () {
    test('entitled account skips promo even when gate is on', () {
      const entitlement = BetaEntitlement(
        hasAccess: true,
        betaPromoGateEnabled: true,
      );
      expect(
        PostAuthRouter.resolve(
          entitlement: entitlement,
          onboardingCompleted: true,
        ),
        PostAuthDestination.home,
      );
      expect(
        PostAuthRouter.resolve(
          entitlement: entitlement,
          onboardingCompleted: false,
        ),
        PostAuthDestination.onboarding,
      );
    });

    test('gate on without access shows promo', () {
      const entitlement = BetaEntitlement(
        hasAccess: false,
        betaPromoGateEnabled: true,
      );
      expect(
        PostAuthRouter.resolve(
          entitlement: entitlement,
          onboardingCompleted: false,
        ),
        PostAuthDestination.promo,
      );
    });

    test('gate off without access soft-passes as entitled', () {
      const entitlement = BetaEntitlement(
        hasAccess: false,
        betaPromoGateEnabled: false,
      );
      expect(entitlement.treatAsEntitled, isTrue);
      expect(entitlement.shouldShowPromo, isFalse);
      expect(
        PostAuthRouter.resolve(
          entitlement: entitlement,
          onboardingCompleted: true,
        ),
        PostAuthDestination.home,
      );
    });

    test('gate on without access is never treatAsEntitled', () {
      const entitlement = BetaEntitlement(
        hasAccess: false,
        betaPromoGateEnabled: true,
      );
      expect(entitlement.treatAsEntitled, isFalse);
      expect(entitlement.shouldShowPromo, isTrue);
    });

    test('entitledGateOff is server gate-off only — not a network fallback', () {
      // PostAuthGateScreen must show retry on Dio/Socket errors, never apply this.
      expect(BetaEntitlement.entitledGateOff.hasAccess, isTrue);
      expect(BetaEntitlement.entitledGateOff.betaPromoGateEnabled, isFalse);
      expect(BetaEntitlement.entitledGateOff.treatAsEntitled, isTrue);
    });

    test('fromJson rejects missing gate flag (no soft-pass default)', () {
      expect(
        () => BetaEntitlement.fromJson({'has_access': false}),
        throwsA(isA<FormatException>()),
      );
      final ok = BetaEntitlement.fromJson({
        'has_access': false,
        'beta_promo_gate_enabled': true,
      });
      expect(ok.treatAsEntitled, isFalse);
      expect(ok.shouldShowPromo, isTrue);
    });
  });

  group('OnboardingPrefs', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('completion persists per user id and version across logout', () async {
      expect(
        await OnboardingPrefs.isCompleted(userId: '42'),
        isFalse,
      );
      await OnboardingPrefs.markCompleted(userId: '42');
      expect(await OnboardingPrefs.isCompleted(userId: '42'), isTrue);
      // Other user still incomplete.
      expect(await OnboardingPrefs.isCompleted(userId: '99'), isFalse);
      // Same user after "logout" (prefs untouched) still done.
      expect(await OnboardingPrefs.isCompleted(userId: '42'), isTrue);
    });
  });

  group('BetaUsageAggregateStore', () {
    late BetaUsageAggregateStore store;
    var batchSeq = 0;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      batchSeq = 0;
      store = BetaUsageAggregateStore(
        dayProvider: () => '2026-07-31',
        buildProvider: () => '2004',
        idFactory: () => 'batch-${++batchSeq}',
      );
    });

    test('retry keeps same batch id and absolute counters (no double)', () async {
      const userId = '7';
      await store.increment(userId, connectAttempts: 1);
      await store.increment(userId, connectSuccesses: 1);

      final first = await store.pendingUpload(userId);
      expect(first, isNotNull);
      expect(first!.clientBatchId, 'batch-1');
      expect(first.connectAttempts, 1);
      expect(first.connectSuccesses, 1);

      // Simulated failed upload: pending unchanged.
      final retry = await store.pendingUpload(userId);
      expect(retry!.clientBatchId, first.clientBatchId);
      expect(retry.connectAttempts, 1);
      expect(retry.connectSuccesses, 1);

      await store.markUploaded(userId, first.clientBatchId);
      expect(await store.pendingUpload(userId), isNull);

      // New activity after ack → new batch, absolute totals continue.
      await store.increment(userId, connectAttempts: 1);
      final next = await store.pendingUpload(userId);
      expect(next!.clientBatchId, 'batch-2');
      expect(next.connectAttempts, 2);
      expect(next.connectSuccesses, 1);
    });
  });
}
