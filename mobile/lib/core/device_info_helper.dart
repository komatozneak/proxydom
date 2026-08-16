import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

class DeviceInfoHelper {
  DeviceInfoHelper._();

  static DeviceInfoPlugin _plugin = DeviceInfoPlugin();

  @visibleForTesting
  static void setPluginForTesting(DeviceInfoPlugin plugin) {
    _plugin = plugin;
  }

  /// Returns human-readable model name (e.g. "Pixel 7", "iPhone 15 Pro").
  static Future<String> getDeviceModelName() async {
    try {
      if (kIsWeb) {
        final webInfo = await _plugin.webBrowserInfo;
        return webInfo.browserName.name;
      }
      if (Platform.isAndroid) {
        final android = await _plugin.androidInfo;
        final model = android.model.trim();
        final brand = android.brand.trim();
        if (model.isNotEmpty) {
          if (brand.isNotEmpty && !model.toLowerCase().startsWith(brand.toLowerCase())) {
            return '$brand $model';
          }
          return model;
        }
        return 'Android';
      }
      if (Platform.isIOS) {
        final ios = await _plugin.iosInfo;
        final model = ios.name.trim();
        if (model.isNotEmpty) return model;
        final uts = ios.utsname.machine.trim();
        if (uts.isNotEmpty) return uts;
        return 'iPhone';
      }
      if (Platform.isMacOS) {
        final mac = await _plugin.macOsInfo;
        return mac.computerName.isNotEmpty ? mac.computerName : 'Mac';
      }
      if (Platform.isWindows) {
        final win = await _plugin.windowsInfo;
        return win.computerName.isNotEmpty ? win.computerName : 'Windows';
      }
      if (Platform.isLinux) {
        final linux = await _plugin.linuxInfo;
        return linux.name.isNotEmpty ? linux.name : 'Linux';
      }
    } catch (_) {}
    return _fallbackPlatformName();
  }

  static String _fallbackPlatformName() {
    if (kIsWeb) return 'Web';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iPhone';
    if (Platform.isMacOS) return 'Mac';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    return 'Device';
  }
}
