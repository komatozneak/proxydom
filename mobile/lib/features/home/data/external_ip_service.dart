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
      headers: {'User-Agent': 'TeremokConnect/0.1'},
    ),
  );
  try {
    final response = await dio.get<String>('https://ifconfig.me/ip');
    final ip = response.data?.trim();
    if (ip == null || ip.isEmpty) return null;
    return ip;
  } on DioException {
    return null;
  }
}
