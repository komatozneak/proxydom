import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/account_api.dart';
import '../data/account_profile.dart';

final accountApiProvider = Provider<AccountApi>((ref) => AccountApi());

final accountProfileProvider =
    AsyncNotifierProvider<AccountProfileNotifier, AccountProfile>(
  AccountProfileNotifier.new,
);

class AccountProfileNotifier extends AsyncNotifier<AccountProfile> {
  @override
  Future<AccountProfile> build() => ref.read(accountApiProvider).fetchMe();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(accountApiProvider).fetchMe());
  }
}
