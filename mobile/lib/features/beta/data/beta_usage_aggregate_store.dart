import 'dart:convert';
import 'dart:math';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'beta_usage_daily.dart';

/// Local daily counters + pending batch for idempotent upload.
///
/// Semantics:
/// - Counters are absolute for the UTC day (never decreased).
/// - [clientBatchId] stays stable until the server acks the snapshot.
/// - Retries resend the same batch id + same absolute values → no double count.
/// - Never blocks VPN; callers fire-and-forget upload.
class BetaUsageAggregateStore {
  BetaUsageAggregateStore({
    SharedPreferences? prefs,
    String? Function()? dayProvider,
    String? Function()? buildProvider,
    String Function()? idFactory,
  })  : _prefsOverride = prefs,
        _dayProvider = dayProvider,
        _buildProvider = buildProvider,
        _idFactory = idFactory ?? _defaultId;

  final SharedPreferences? _prefsOverride;
  final String? Function()? _dayProvider;
  final String? Function()? _buildProvider;
  final String Function() _idFactory;

  static const _keyPrefix = 'beta_usage_daily_v1';

  Future<SharedPreferences> get _prefs async =>
      _prefsOverride ?? SharedPreferences.getInstance();

  String get _day =>
      _dayProvider?.call() ??
      DateTime.now().toUtc().toIso8601String().substring(0, 10);

  Future<String> _appBuild() async {
    final override = _buildProvider?.call();
    if (override != null) return override;
    try {
      final info = await PackageInfo.fromPlatform();
      return info.buildNumber;
    } catch (_) {
      return '0';
    }
  }

  String _storageKey(String userId, String day) =>
      '${_keyPrefix}_${userId}_$day';

  Future<_DayState> _load(String userId) async {
    final prefs = await _prefs;
    final day = _day;
    final raw = prefs.getString(_storageKey(userId, day));
    if (raw == null || raw.isEmpty) {
      return _DayState.empty(day: day);
    }
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return _DayState.fromJson(map);
    } catch (_) {
      return _DayState.empty(day: day);
    }
  }

  Future<void> _save(String userId, _DayState state) async {
    final prefs = await _prefs;
    await prefs.setString(
      _storageKey(userId, state.day),
      jsonEncode(state.toJson()),
    );
  }

  Future<BetaUsageDailySnapshot> snapshot(String userId) async {
    final state = await _load(userId);
    final build = await _appBuild();
    return state.toSnapshot(appBuild: build);
  }

  Future<void> increment(
    String userId, {
    int connectAttempts = 0,
    int connectSuccesses = 0,
    int reconnectCount = 0,
    int sessionSeconds = 0,
    int regionChangeCount = 0,
    int accessStatusLoadOkCount = 0,
    int diagnosticReportSentCount = 0,
    int crashCount = 0,
    bool? onboardingCompleted,
  }) async {
    if (userId.isEmpty) return;
    final state = await _load(userId);
    final next = state.copyWith(
      connectAttempts: state.connectAttempts + max(0, connectAttempts),
      connectSuccesses: state.connectSuccesses + max(0, connectSuccesses),
      reconnectCount: state.reconnectCount + max(0, reconnectCount),
      sessionSeconds:
          min(86400, state.sessionSeconds + max(0, sessionSeconds)),
      regionChangeCount: state.regionChangeCount + max(0, regionChangeCount),
      accessStatusLoadOkCount:
          state.accessStatusLoadOkCount + max(0, accessStatusLoadOkCount),
      diagnosticReportSentCount: state.diagnosticReportSentCount +
          max(0, diagnosticReportSentCount),
      crashCount: state.crashCount + max(0, crashCount),
      onboardingCompleted:
          onboardingCompleted == true ? true : state.onboardingCompleted,
      // New deltas after an ack need a fresh batch id.
      clientBatchId: state.acked
          ? _idFactory()
          : state.clientBatchId,
      acked: false,
    );
    await _save(userId, next);
  }

  /// Mark current pending batch as acknowledged after successful upload.
  Future<void> markUploaded(String userId, String clientBatchId) async {
    final state = await _load(userId);
    if (state.clientBatchId != clientBatchId) return;
    await _save(userId, state.copyWith(acked: true));
  }

  /// Pending snapshot if not yet acked (for retry).
  Future<BetaUsageDailySnapshot?> pendingUpload(String userId) async {
    final state = await _load(userId);
    if (state.acked) return null;
    if (!_hasActivity(state)) return null;
    final build = await _appBuild();
    return state.toSnapshot(appBuild: build);
  }

  bool _hasActivity(_DayState s) =>
      s.onboardingCompleted ||
      s.connectAttempts > 0 ||
      s.connectSuccesses > 0 ||
      s.reconnectCount > 0 ||
      s.sessionSeconds > 0 ||
      s.regionChangeCount > 0 ||
      s.accessStatusLoadOkCount > 0 ||
      s.diagnosticReportSentCount > 0 ||
      s.crashCount > 0;

  static String _defaultId() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

class _DayState {
  const _DayState({
    required this.day,
    required this.clientBatchId,
    required this.acked,
    required this.onboardingCompleted,
    required this.connectAttempts,
    required this.connectSuccesses,
    required this.reconnectCount,
    required this.sessionSeconds,
    required this.regionChangeCount,
    required this.accessStatusLoadOkCount,
    required this.diagnosticReportSentCount,
    required this.crashCount,
  });

  factory _DayState.empty({required String day}) {
    return _DayState(
      day: day,
      clientBatchId: '',
      acked: true,
      onboardingCompleted: false,
      connectAttempts: 0,
      connectSuccesses: 0,
      reconnectCount: 0,
      sessionSeconds: 0,
      regionChangeCount: 0,
      accessStatusLoadOkCount: 0,
      diagnosticReportSentCount: 0,
      crashCount: 0,
    );
  }

  final String day;
  final String clientBatchId;
  final bool acked;
  final bool onboardingCompleted;
  final int connectAttempts;
  final int connectSuccesses;
  final int reconnectCount;
  final int sessionSeconds;
  final int regionChangeCount;
  final int accessStatusLoadOkCount;
  final int diagnosticReportSentCount;
  final int crashCount;

  _DayState copyWith({
    String? clientBatchId,
    bool? acked,
    bool? onboardingCompleted,
    int? connectAttempts,
    int? connectSuccesses,
    int? reconnectCount,
    int? sessionSeconds,
    int? regionChangeCount,
    int? accessStatusLoadOkCount,
    int? diagnosticReportSentCount,
    int? crashCount,
  }) {
    return _DayState(
      day: day,
      clientBatchId: clientBatchId ?? this.clientBatchId,
      acked: acked ?? this.acked,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      connectAttempts: connectAttempts ?? this.connectAttempts,
      connectSuccesses: connectSuccesses ?? this.connectSuccesses,
      reconnectCount: reconnectCount ?? this.reconnectCount,
      sessionSeconds: sessionSeconds ?? this.sessionSeconds,
      regionChangeCount: regionChangeCount ?? this.regionChangeCount,
      accessStatusLoadOkCount:
          accessStatusLoadOkCount ?? this.accessStatusLoadOkCount,
      diagnosticReportSentCount:
          diagnosticReportSentCount ?? this.diagnosticReportSentCount,
      crashCount: crashCount ?? this.crashCount,
    );
  }

  Map<String, dynamic> toJson() => {
        'day': day,
        'client_batch_id': clientBatchId,
        'acked': acked,
        'onboarding_completed': onboardingCompleted,
        'connect_attempts': connectAttempts,
        'connect_successes': connectSuccesses,
        'reconnect_count': reconnectCount,
        'session_seconds': sessionSeconds,
        'region_change_count': regionChangeCount,
        'access_status_load_ok_count': accessStatusLoadOkCount,
        'diagnostic_report_sent_count': diagnosticReportSentCount,
        'crash_count': crashCount,
      };

  factory _DayState.fromJson(Map<String, dynamic> json) {
    return _DayState(
      day: json['day'] as String? ?? '',
      clientBatchId: json['client_batch_id'] as String? ?? '',
      acked: json['acked'] == true,
      onboardingCompleted: json['onboarding_completed'] == true,
      connectAttempts: (json['connect_attempts'] as num?)?.toInt() ?? 0,
      connectSuccesses: (json['connect_successes'] as num?)?.toInt() ?? 0,
      reconnectCount: (json['reconnect_count'] as num?)?.toInt() ?? 0,
      sessionSeconds: (json['session_seconds'] as num?)?.toInt() ?? 0,
      regionChangeCount: (json['region_change_count'] as num?)?.toInt() ?? 0,
      accessStatusLoadOkCount:
          (json['access_status_load_ok_count'] as num?)?.toInt() ?? 0,
      diagnosticReportSentCount:
          (json['diagnostic_report_sent_count'] as num?)?.toInt() ?? 0,
      crashCount: (json['crash_count'] as num?)?.toInt() ?? 0,
    );
  }

  BetaUsageDailySnapshot toSnapshot({required String appBuild}) {
    return BetaUsageDailySnapshot(
      day: day,
      appBuild: appBuild,
      clientBatchId: clientBatchId,
      onboardingCompleted: onboardingCompleted,
      connectAttempts: connectAttempts,
      connectSuccesses: connectSuccesses,
      reconnectCount: reconnectCount,
      sessionSeconds: sessionSeconds,
      regionChangeCount: regionChangeCount,
      accessStatusLoadOkCount: accessStatusLoadOkCount,
      diagnosticReportSentCount: diagnosticReportSentCount,
      crashCount: crashCount,
    );
  }
}
