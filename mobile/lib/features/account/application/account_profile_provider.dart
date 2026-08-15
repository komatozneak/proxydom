import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../session/application/session_projections.dart';
import '../../session/application/session_provider.dart';
import '../data/account_api.dart';
import '../data/account_profile.dart';

final accountApiProvider = Provider<AccountApi>((ref) => AccountApi());

final accountProfileProvider =
    AsyncNotifierProvider<AccountProfileNotifier, AccountProfile>(
  AccountProfileNotifier.new,
);

class AccountProfileNotifier extends AsyncNotifier<AccountProfile> {
  @override
  Future<AccountProfile> build() async {
    final session = ref.watch(sessionProvider).valueOrNull;
    if (session != null) {
      return profileFromSession(session);
    }
    return ref.read(accountApiProvider).fetchMe();
  }

  Future<void> refresh() async {
    await ref.read(sessionProvider.notifier).refresh();
    final session = ref.read(sessionProvider).valueOrNull;
    if (session != null) {
      state = AsyncData(profileFromSession(session));
      return;
    }
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(accountApiProvider).fetchMe());
  }
}
