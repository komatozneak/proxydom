import 'package:dio/dio.dart';
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
    final auth = await ref.watch(authProvider.future);
    if (auth is! AuthStateAuthenticated) {
      return SubscriptionStatus.empty;
    }
    final session = ref.watch(sessionProvider).valueOrNull;
    if (session != null) {
      return subscriptionFromSession(session);
    }
    return _fetch();
  }

  Future<SubscriptionStatus> _fetch() async {
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

  Future<void> refresh() async {
    await ref.read(sessionProvider.notifier).refresh();
    final session = ref.read(sessionProvider).valueOrNull;
    if (session != null) {
      state = AsyncData(subscriptionFromSession(session));
      return;
    }
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }
}
