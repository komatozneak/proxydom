import '../../../core/device_info_helper.dart';
import '../../../core/device_platform.dart';
import '../../../core/install_id_storage.dart';

/// Envelope sent with GET /vpn/config for per-device slots.
class DeviceEnvelope {
  const DeviceEnvelope({
    required this.deviceId,
    this.deviceName,
    this.platform,
  });

  final String deviceId;
  final String? deviceName;
  final String? platform;

  Map<String, String> toQueryParameters() => {
        'device_id': deviceId,
        if (deviceName != null && deviceName!.isNotEmpty)
          'device_name': deviceName!,
        if (platform != null && platform!.isNotEmpty) 'platform': platform!,
      };
}

Future<DeviceEnvelope> buildDeviceEnvelope({
  InstallIdStorage? storage,
  Future<String> Function()? deviceNameReader,
}) async {
  final id = await (storage ?? InstallIdStorage.instance).getOrCreate();
  final name = await (deviceNameReader ?? DeviceInfoHelper.getDeviceModelName)();
  return DeviceEnvelope(
    deviceId: id,
    deviceName: name,
    platform: devicePlatformCode(),
  );
}
