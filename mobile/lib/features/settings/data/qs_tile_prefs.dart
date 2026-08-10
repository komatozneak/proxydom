import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Quick Settings tile helpers (Android only).
class QsTilePrefs {
  QsTilePrefs._();

  static const _channel = MethodChannel('teremok/vpn');

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Prompt the system to pin [TeremokTileService].
  ///
  /// Returns one of: `added`, `already_added`, `not_added`, `manual`.
  static Future<String> requestAdd() async {
    if (!isSupported) return 'manual';
    try {
      final result = await _channel.invokeMethod<String>('requestAddQsTile');
      return result ?? 'manual';
    } on PlatformException {
      return 'manual';
    } on MissingPluginException {
      return 'manual';
    }
  }
}
