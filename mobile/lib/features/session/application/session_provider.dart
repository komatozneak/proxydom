import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_client.dart';
import '../../../core/api_secret_storage.dart';
import '../../auth/application/auth_provider.dart';
import '../../auth/application/auth_state.dart';
import '../data/account_session_snapshot.dart';

/// Single client SoT for account + devices + entitlement (ADR 016).
final sessionProvider =
    AsyncNotifierProvider<SessionNotifier, AccountSessionSnapshot?>(
  SessionNotifier.new,
);

/// True when ``incomingVersion`` should replace the cached snapshot.
bool sessionShouldApply(int incomingVersion, int? currentVersion) {
  if (currentVersion == null) return true;
  return incomingVersion > currentVersion;
}

class SessionNotifier extends AsyncNotifier<AccountSessionSnapshot?> {
  @override
  Future<AccountSessionSnapshot?> build() async {
    final auth = await ref.watch(authProvider.future);
    if (auth is! AuthStateAuthenticated) return null;
    return _fetch();
  }

  Future<AccountSessionSnapshot?> _fetch() async {
    final cached = state.valueOrNull;
    final headers = <String, dynamic>{};
    if (cached != null && cached.accountId > 0 && cached.version > 0) {
      headers['If-None-Match'] = '"${cached.accountId}-${cached.version}"';
    }
    final resp = await ApiClient.instance.get(
      '/session',
      options: Options(headers: headers),
    );
    if (resp.statusCode == 304) {
      return cached;
    }
    if (resp.statusCode != 200 || resp.data is! Map) return null;
    return AccountSessionSnapshot.fromJson(
      Map<String, dynamic>.from(resp.data as Map),
    );
  }

  /// Apply a mutation snapshot. Older versions are discarded.
  Future<void> apply(AccountSessionSnapshot snap) async {
    final current = state.valueOrNull;
    if (!sessionShouldApply(snap.version, current?.version)) {
      return;
    }
    final secret = snap.apiSecret?.trim();
    if (secret != null && secret.isNotEmpty) {
      await ApiSecretStorage.instance.save(secret);
    }
    state = AsyncData(snap);
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_fetch);
  }
}

AccountSessionSnapshot? sessionFromUnknown(Object? raw) {
  if (raw is Map) {
    return AccountSessionSnapshot.fromJson(Map<String, dynamic>.from(raw));
  }
  return null;
}
