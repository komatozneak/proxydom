import 'package:dio/dio.dart';

/// Result of a GeoIP lookup for a VPS egress host.
class GeoIpResult {
  final String country;
  final String countryCode; // "SE", "DE", etc.
  final String city;
  final String region;

  const GeoIpResult({
    required this.country,
    required this.countryCode,
    required this.city,
    required this.region,
  });

  factory GeoIpResult.fromJson(Map<String, dynamic> json) {
    return GeoIpResult(
      country: json['country'] as String? ?? 'Unknown',
      countryCode: json['countryCode'] as String? ?? '',
      city: json['city'] as String? ?? '',
      region: json['regionName'] as String? ?? '',
    );
  }

  /// Convert country code to flag emoji, e.g. "SE" → "🇸🇪"
  String get flagEmoji {
    if (countryCode.length != 2) return '🌍';
    final upper = countryCode.toUpperCase();
    const base = 0x1F1E6;
    final a = upper.codeUnitAt(0) - 65 + base;
    final b = upper.codeUnitAt(1) - 65 + base;
    return String.fromCharCode(a) + String.fromCharCode(b);
  }

  /// ip-api returns English `country`; RU uses a small override map.
  String displayCountry(String locale) {
    if (locale == 'ru') {
      return _countryRuOverrides[countryCode.toUpperCase()] ?? country;
    }
    return country;
  }

  String displayCity(String locale) {
    if (locale == 'ru') {
      final code = countryCode.toUpperCase();
      final override = _cityRuOverrides[code];
      if (override != null) return override;
      if (city.isNotEmpty) return city;
      return region;
    }
    if (city.isNotEmpty) return city;
    return region;
  }
}

const _countryRuOverrides = {
  'SE': 'Швеция',
  'NL': 'Нидерланды',
  'DE': 'Германия',
  'US': 'США',
  'FR': 'Франция',
  'GB': 'Великобритания',
  'FI': 'Финляндия',
  'EE': 'Эстония',
  'LV': 'Латвия',
  'LT': 'Литва',
};

/// City overrides keyed by country when we prefer a canonical hub name.
const _cityRuOverrides = {
  'SE': 'Стокгольм',
  'NL': 'Амстердам',
  'DE': 'Франкфурт',
  'US': 'Нью-Йорк',
};

/// Free GeoIP via ip-api.com (no key, HTTP, ~45 req/min). Cached in-memory.
class GeoIpService {
  GeoIpService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 5),
                sendTimeout: const Duration(seconds: 5),
                receiveTimeout: const Duration(seconds: 5),
                responseType: ResponseType.json,
                validateStatus: (s) => s != null && s < 500,
              ),
            );

  static final GeoIpService instance = GeoIpService();

  final Dio _dio;
  final Map<String, GeoIpResult> _cache = {};
  final Map<String, Future<GeoIpResult?>> _inflight = {};

  /// Sync cache read (after [lookup] / [prefetch]).
  GeoIpResult? cached(String ip) => _cache[ip.trim()];

  /// Look up [ip]; returns null on failure (silent).
  Future<GeoIpResult?> lookup(String ip) async {
    final key = ip.trim();
    if (key.isEmpty) return null;
    final hit = _cache[key];
    if (hit != null) return hit;

    final pending = _inflight[key];
    if (pending != null) return pending;

    final future = _fetch(key);
    _inflight[key] = future;
    try {
      return await future;
    } finally {
      _inflight.remove(key);
    }
  }

  Future<void> prefetch(Iterable<String> ips) async {
    final unique = ips.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    await Future.wait(unique.map(lookup));
  }

  Future<GeoIpResult?> _fetch(String ip) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        'http://ip-api.com/json/$ip',
        queryParameters: {
          'fields': 'status,country,countryCode,city,regionName',
        },
      );
      final data = response.data;
      if (data == null || data['status'] != 'success') return null;
      final result = GeoIpResult.fromJson(data);
      _cache[ip] = result;
      return result;
    } catch (_) {
      return null;
    }
  }

  /// Test helper — clear memory cache.
  void clearCache() {
    _cache.clear();
    _inflight.clear();
  }
}
