import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_provider.dart';
import '../../auth/application/auth_state.dart';
import '../data/beta_api.dart';
import '../data/beta_usage_aggregate_store.dart';
import '../data/jwt_subject.dart';
import 'beta_providers.dart';

/// Fire-and-forget usage hooks. Never awaits on the VPN hot path.
class BetaUsageTracker {
  BetaUsageTracker(this._ref);

  final Ref _ref;

  BetaUsageAggregateStore get _store => _ref.read(betaUsageStoreProvider);
  BetaApi get _api => _ref.read(betaApiProvider);

  String? _userId() {
    final auth = _ref.read(authProvider).valueOrNull;
    if (auth is! AuthStateAuthenticated) return null;
    return jwtSubject(auth.accessToken);
  }

  void _bump(
    Future<void> Function(String userId) action, {
    bool flush = true,
  }) {
    final userId = _userId();
    if (userId == null) return;
    unawaited(() async {
      try {
        await action(userId);
        if (flush) await flushPending();
      } catch (e, st) {
        debugPrint('beta.usage: $e\n$st');
      }
    }());
  }

  void recordConnectAttempt() => _bump(
        (id) => _store.increment(id, connectAttempts: 1),
      );

  void recordConnectSuccess() => _bump(
        (id) => _store.increment(id, connectSuccesses: 1),
      );

  void recordReconnect() => _bump(
        (id) => _store.increment(id, reconnectCount: 1),
      );

  void recordSessionSeconds(int seconds) {
    if (seconds <= 0) return;
    _bump((id) => _store.increment(id, sessionSeconds: seconds));
  }

  void recordRegionChange() => _bump(
        (id) => _store.increment(id, regionChangeCount: 1),
      );

  void recordAccessStatusLoadOk() => _bump(
        (id) => _store.increment(id, accessStatusLoadOkCount: 1),
      );

  void recordDiagnosticReportSent() => _bump(
        (id) => _store.increment(id, diagnosticReportSentCount: 1),
      );

  void recordCrash() => _bump(
        (id) => _store.increment(id, crashCount: 1),
        flush: false,
      );

  void recordOnboardingCompleted() => _bump(
        (id) => _store.increment(id, onboardingCompleted: true),
      );

  /// Upload pending batch; retries keep the same client_batch_id.
  Future<void> flushPending() async {
    final userId = _userId();
    if (userId == null) return;
    final pending = await _store.pendingUpload(userId);
    if (pending == null) return;
    try {
      await _api.uploadUsageDaily(pending);
      await _store.markUploaded(userId, pending.clientBatchId);
    } catch (e) {
      debugPrint('beta.usage.upload_failed: $e');
    }
  }
}

final betaUsageTrackerProvider = Provider<BetaUsageTracker>(
  BetaUsageTracker.new,
);
