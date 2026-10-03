import 'package:dio/dio.dart';

/// Fetches the device's public IP as seen from the internet.
///
/// When VPN is active, traffic routes through the tunnel — the result
/// should match the VPS egress IP (E2E verification on Pixel).
Future<String?> fetchExternalIp() async {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      responseType: ResponseType.plain,
      headers: {'User-Agent': 'ProxyDom/0.1'},
    ),
  );
  try {
    // Prefer IPv4 for E2E checks (ifconfig.me may return VPS IPv6 first).
    final response = await dio.get<String>(
      'https://ipv4.icanhazip.com',
      options: Options(followRedirects: true),
    );
    final ip = response.data?.trim();
    if (ip == null || ip.isEmpty) return null;
    return ip;
  } on DioException {
    try {
      final fallback = await dio.get<String>('https://ifconfig.me/ip');
      final ip = fallback.data?.trim();
      if (ip == null || ip.isEmpty) return null;
      return ip;
    } on DioException {
      return null;
    }
  }
}
