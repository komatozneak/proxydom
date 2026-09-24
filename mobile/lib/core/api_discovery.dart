import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'config.dart';
import 'diagnostics/app_log_buffer.dart';

/// Host discovery + failover for control-plane API (ADR 009).
class ApiDiscovery {
  ApiDiscovery._();
  static final ApiDiscovery instance = ApiDiscovery._();

  static const _prefsHostsKey = 'tc.api_discovery_hosts';
  static const _prefsOriginKey = 'tc.api_active_origin';

  /// Per-origin probe budget (cold start must not sit on LaunchScreen).
  @visibleForTesting
  static const Duration probeTimeout = Duration(seconds: 2);

  List<String> _hosts = List<String>.from(AppConfig.discoverySeedHosts);

  List<String> get hosts => List.unmodifiable(_hosts);

  /// Apply last-known origin from prefs without network (safe before [runApp]).
  Future<void> loadCachedOrigin() async {
    await _loadCachedHosts();
  }

  /// Probe `/healthz` across seed + refreshed hosts; update Dio baseUrl.
  Future<String?> refreshAndSelect({Dio? probeClient}) async {
    await _loadCachedHosts();
    await _refreshFromResources(probeClient: probeClient);

    for (final origin in _hosts) {
      if (await _healthy(origin, probeClient: probeClient)) {
        await _activate(origin);
        return origin;
      }
    }
    AppLogBuffer.instance.debug(
      'api.discovery: no healthy host among ${_hosts.length}',
    );
    return null;
  }

  Future<void> _loadCachedHosts() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getStringList(_prefsHostsKey);
    if (cached != null && cached.isNotEmpty) {
      _hosts = _merge(AppConfig.discoverySeedHosts, cached);
    }
    final active = prefs.getString(_prefsOriginKey);
    if (active != null && active.isNotEmpty) {
      ApiClient.setBaseOrigin(active);
      AppLogBuffer.instance.debug('api.discovery cached_origin=$active');
    }
  }

  Future<void> _refreshFromResources({Dio? probeClient}) async {
    final dio = probeClient ??
        Dio(
          BaseOptions(
            connectTimeout: probeTimeout,
            receiveTimeout: probeTimeout,
            validateStatus: (s) => s != null && s < 500,
          ),
        );
    for (final origin in List<String>.from(_hosts)) {
      final sw = Stopwatch()..start();
      try {
        final resp = await dio.get<Map<String, dynamic>>(
          '$origin/v2/app/resources',
        );
        AppLogBuffer.instance.debug(
          'api.discovery resources origin=$origin ms=${sw.elapsedMilliseconds} '
          'status=${resp.statusCode}',
        );
        if (resp.statusCode == 200 && resp.data is Map) {
          final raw = resp.data!['api_hosts'];
          if (raw is List) {
            final fetched = raw
                .whereType<String>()
                .map((e) => e.trim().replaceAll(RegExp(r'/+$'), ''))
                .where((e) => e.startsWith('http'))
                .toList();
            if (fetched.isNotEmpty) {
              _hosts = _merge(_hosts, fetched);
              final prefs = await SharedPreferences.getInstance();
              await prefs.setStringList(_prefsHostsKey, _hosts);
              return;
            }
          }
        }
      } catch (e) {
        AppLogBuffer.instance.debug(
          'api.discovery resources origin=$origin '
          'ms=${sw.elapsedMilliseconds} fail',
        );
        debugPrint('api.discovery resources fail $origin: $e');
      }
    }
  }

  Future<bool> _healthy(String origin, {Dio? probeClient}) async {
    final dio = probeClient ??
        Dio(
          BaseOptions(
            connectTimeout: probeTimeout,
            receiveTimeout: probeTimeout,
            validateStatus: (s) => s != null && s < 500,
          ),
        );
    final sw = Stopwatch()..start();
    try {
      final resp = await dio.get('$origin/healthz');
      final ok = resp.statusCode == 200;
      AppLogBuffer.instance.debug(
        'api.discovery healthz origin=$origin '
        'ms=${sw.elapsedMilliseconds} ok=$ok',
      );
      return ok;
    } catch (_) {
      try {
        final resp = await dio.get('$origin/health');
        final ok = resp.statusCode == 200;
        AppLogBuffer.instance.debug(
          'api.discovery health origin=$origin '
          'ms=${sw.elapsedMilliseconds} ok=$ok',
        );
        return ok;
      } catch (_) {
        AppLogBuffer.instance.debug(
          'api.discovery health origin=$origin '
          'ms=${sw.elapsedMilliseconds} ok=false',
        );
        return false;
      }
    }
  }

  Future<void> _activate(String origin) async {
    ApiClient.setBaseOrigin(origin);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsOriginKey, origin);
    AppLogBuffer.instance.debug('api.discovery: active=$origin');
    debugPrint('api.discovery: active=$origin');
  }

  List<String> _merge(List<String> a, List<String> b) {
    final out = <String>[];
    final seen = <String>{};
    for (final h in [...a, ...b]) {
      final n = h.trim().replaceAll(RegExp(r'/+$'), '');
      if (n.isEmpty || !seen.add(n)) continue;
      out.add(n);
    }
    return out;
  }
}
