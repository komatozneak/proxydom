import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import '../../../core/device_info_helper.dart';
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
    platform: _platformCode(),
  );
}

String _platformCode() {
  if (kIsWeb) return 'web';
  if (Platform.isAndroid) return 'android';
  if (Platform.isIOS) return 'ios';
  if (Platform.isMacOS) return 'macos';
  if (Platform.isWindows) return 'windows';
  if (Platform.isLinux) return 'linux';
  return 'unknown';
}
