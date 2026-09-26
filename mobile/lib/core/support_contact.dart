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
    return launchUrl(composeChatUri(text), mode: LaunchMode.externalApplication);
  }

  /// Opens the product bot. Do not put a diagnostic dump in ``text=`` —
  /// Telegram returns HTTP 400 on oversized share URLs.
  static Future<bool> openBot() async {
    return launchUrl(composeBotUri(), mode: LaunchMode.externalApplication);
  }

  static Uri composeBotUri() {
    return Uri.https('t.me', AppConfig.telegramBotUsername);
  }

  /// `https://t.me/<support>?text=` — same path as [open].
  static Uri composeChatUri(String text) {
    return Uri.https(
      't.me',
      AppConfig.supportTelegramUsername,
      {'text': text},
    );
  }

  /// Telegram share `text=` is much smaller than Bot API POST (4096).
  static const int telegramShareMaxChars = 3500;

  static String clipForChat(String text) {
    const note = '… (обрезано, полный отчёт в буфере обмена)\n';
    if (text.length <= telegramShareMaxChars) return text;
    final budget = telegramShareMaxChars - note.length;
    if (budget <= 0) return text.substring(0, telegramShareMaxChars);
    return '$note${text.substring(text.length - budget)}';
  }

  static String _template({
    required String deviceId,
    required String version,
    required String screen,
  }) {
    return '''
Здравствуйте! Нужна помощь с доступом Прокси Дом.

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
