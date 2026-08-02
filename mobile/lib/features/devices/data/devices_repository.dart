import 'package:dio/dio.dart';

import '../../../core/api_client.dart';

class DeviceSlot {
  const DeviceSlot({
    required this.id,
    required this.status,
    required this.createdAt,
    this.deviceName,
    this.platform,
    this.lastSeenAt,
    this.isCurrent = false,
  });

  final int id;
  final String? deviceName;
  final String? platform;
  final String status;
  final DateTime? lastSeenAt;
  final DateTime createdAt;
  final bool isCurrent;

  factory DeviceSlot.fromJson(Map<String, dynamic> json) {
    return DeviceSlot(
      id: json['id'] as int,
      deviceName: json['device_name'] as String?,
      platform: json['platform'] as String?,
      status: json['status'] as String? ?? 'active',
      lastSeenAt: json['last_seen_at'] != null
          ? DateTime.tryParse(json['last_seen_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      isCurrent: json['is_current'] as bool? ?? false,
    );
  }
}

class DeviceListResult {
  const DeviceListResult({
    required this.devices,
    required this.activeCount,
    required this.maxDevices,
  });

  final List<DeviceSlot> devices;
  final int activeCount;
  final int maxDevices;

  factory DeviceListResult.fromJson(Map<String, dynamic> json) {
    final raw = json['devices'] as List<dynamic>? ?? const [];
    return DeviceListResult(
      devices: raw
          .map((e) => DeviceSlot.fromJson(e as Map<String, dynamic>))
          .toList(),
      activeCount: json['active_count'] as int? ?? raw.length,
      maxDevices: json['max_devices'] as int? ?? 10,
    );
  }
}

class DevicesRepository {
  DevicesRepository();

  final Dio _dio = ApiClient.instance;

  Future<DeviceListResult> listDevices({String? currentDeviceId}) async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '/devices',
      queryParameters: {
        if (currentDeviceId != null && currentDeviceId.isNotEmpty)
          'device_id': currentDeviceId,
      },
    );
    if (resp.statusCode == 200 && resp.data != null) {
      return DeviceListResult.fromJson(resp.data!);
    }
    throw DioException(
      requestOptions: resp.requestOptions,
      response: resp,
      type: DioExceptionType.badResponse,
    );
  }

  Future<void> revokeDevice(int devicePk) async {
    final resp = await _dio.delete<void>('/devices/$devicePk');
    if (resp.statusCode != 204 && resp.statusCode != 200) {
      throw DioException(
        requestOptions: resp.requestOptions,
        response: resp,
        type: DioExceptionType.badResponse,
      );
    }
  }
}
