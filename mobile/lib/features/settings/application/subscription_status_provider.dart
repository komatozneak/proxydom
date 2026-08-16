import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_client.dart';
import '../../auth/application/auth_provider.dart';
import '../../auth/application/auth_state.dart';
import '../../beta/application/beta_usage_tracker.dart';
import '../../session/application/session_projections.dart';
import '../../session/application/session_provider.dart';
import '../data/subscription_status.dart';

final subscriptionStatusProvider =
    AsyncNotifierProvider.autoDispose<SubscriptionStatusNotifier,
        SubscriptionStatus>(
  SubscriptionStatusNotifier.new,
);

class SubscriptionStatusNotifier
    extends AutoDisposeAsyncNotifier<SubscriptionStatus> {
  @override
  Future<SubscriptionStatus> build() async {
    // Listen (do not watch) session: a 304/refresh must not rebuild Free quota
    // into AsyncLoading. Paid upgrades still project immediately.
    ref.listen(sessionProvider, (previous, next) {
      final snap = next.valueOrNull;
      if (snap != null && snap.tier != 'free') {
        state = AsyncData(subscriptionFromSession(snap));
      }
    });

    final auth = await ref.watch(authProvider.future);
    if (auth is! AuthStateAuthenticated) {
      return SubscriptionStatus.empty;
    }
    final session = ref.read(sessionProvider).valueOrNull;
    if (session != null && session.tier != 'free') {
      return subscriptionFromSession(session);
    }
    return loadFreeQuota();
  }

  /// Free-tier source: GET `/billing/subscription` (session has no quota).
  @visibleForTesting
  Future<SubscriptionStatus> loadFreeQuota() async {
    // Leading slash required: Dio joins as baseUrl + path (no separator).
    // Without it → /api/v1billing/subscription → 404 → Settings load error.
    final resp = await ApiClient.instance.get<Map<String, dynamic>>(
      '/billing/subscription',
    );
    if (resp.statusCode == 401) {
      return SubscriptionStatus.empty;
    }
    if (resp.statusCode != 200 || resp.data == null) {
      throw DioException(
        requestOptions: resp.requestOptions,
        response: resp,
        message: 'subscription status failed: ${resp.statusCode}',
      );
    }
    try {
      ref.read(betaUsageTrackerProvider).recordAccessStatusLoadOk();
    } on StateError {
      // Provider disposed in tests.
    }
    return SubscriptionStatus.fromJson(resp.data!);
  }

  /// Reload this notifier's source only. Does not refresh [sessionProvider]
  /// (that would invalidate watchers / this notifier mid-await).
  Future<void> refresh() async {
    final previous = state.asData?.value;
    final session = ref.read(sessionProvider).valueOrNull;
    if (session != null && session.tier != 'free') {
      state = AsyncData(subscriptionFromSession(session));
      return;
    }
    final next = await AsyncValue.guard(loadFreeQuota);
    if (next.hasValue) {
      _setIfAlive(next);
    } else if (previous != null) {
      _setIfAlive(AsyncData(previous));
    } else {
      _setIfAlive(next);
    }
  }

  void _setIfAlive(AsyncValue<SubscriptionStatus> next) {
    try {
      state = next;
    } on StateError {
      // Notifier disposed while the request was in flight.
    } on AssertionError {
      // Provider invalidated (e.g. auth) while refresh awaited.
    }
  }
}
