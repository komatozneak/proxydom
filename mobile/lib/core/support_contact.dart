import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'config.dart';
import 'install_id_storage.dart';

/// Opens Telegram with a prefilled support ticket (device identity only).
///
/// User decides Send vs cancel; payment receipt is requested by support in chat.
class SupportContact {
  SupportContact._();

  /// [screen] — where the user tapped (Настройки / Активация / …).
  static Future<bool> open({required String screen}) async {
    final deviceId = await _deviceId();
    final version = await _versionLabel();
    final text = _template(
      deviceId: deviceId,
      version: version,
      screen: screen,
    );
    final uri = Uri.https(
      't.me',
      AppConfig.supportTelegramUsername,
      {'text': text},
    );
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static String _template({
    required String deviceId,
    required String version,
    required String screen,
  }) {
    return '''
Здравствуйте! Нужна помощь с доступом Teremok VPN.

ID устройства: $deviceId
Версия: $version
ОС: ${_osLine()}
Откуда: $screen
'''.trim();
  }

  static String _osLine() {
    try {
      if (kIsWeb) return 'web';
      return '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    } catch (_) {
      return 'неизвестна';
    }
  }

  static Future<String> _deviceId() async {
    try {
      return await InstallIdStorage.instance.getOrCreate();
    } catch (e, st) {
      debugPrint('support.device_id_failed: $e\n$st');
      return 'неизвестен';
    }
  }

  static Future<String> _versionLabel() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return '${info.version}+${info.buildNumber}';
    } catch (_) {
      return 'неизвестна';
    }
  }
}
