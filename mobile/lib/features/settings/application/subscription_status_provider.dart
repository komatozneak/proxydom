import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_client.dart';
import '../../auth/application/auth_provider.dart';
import '../../auth/application/auth_state.dart';
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
    return _fetch();
  }

  Future<SubscriptionStatus> _fetch() async {
    final resp = await ApiClient.instance.get<Map<String, dynamic>>(
      'billing/subscription',
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
    return SubscriptionStatus.fromJson(resp.data!);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }
}
