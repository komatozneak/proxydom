import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// MethodChannel shared with VPN native (see [VpnChannelRegistry]).
const MethodChannel kDeviceLabelChannel = MethodChannel('proxydom/vpn');

const _genericLabels = {
  'android',
  'device',
  'unknown',
  'generic',
  'phone',
  'ios',
  'iphone',
  'sdk',
};

bool _isGeneric(String? value) {
  if (value == null) return true;
  final n = value.trim().toLowerCase();
  if (n.isEmpty) return true;
  return _genericLabels.contains(n);
}

String _titleCaseWord(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return trimmed;
  if (trimmed.length == 1) return trimmed.toUpperCase();
  return '${trimmed[0].toUpperCase()}${trimmed.substring(1).toLowerCase()}';
}

String _clip128(String value) =>
    value.length <= 128 ? value : value.substring(0, 128);

/// Human-readable label from Android [Build] + Settings device name.
///
/// Prefers the user-visible name (often «Pixel 8» / «Galaxy S24»). Falls back
/// to manufacturer + model, skipping a redundant «Google» prefix on Pixels.
String formatOsDeviceLabel({
  String? settingsName,
  String? brand,
  String? manufacturer,
  String? model,
  String fallback = 'Android',
}) {
  final setting = settingsName?.trim() ?? '';
  if (setting.isNotEmpty && !_isGeneric(setting)) {
    return _clip128(setting);
  }

  final rawModel = (model ?? '').trim();
  final mfgRaw = (manufacturer ?? '').trim();
  final brandRaw = (brand ?? '').trim();
  final mfg = _isGeneric(mfgRaw) ? brandRaw : mfgRaw;
  final mfgKey = mfg.toLowerCase();

  if (rawModel.isNotEmpty && !_isGeneric(rawModel)) {
    final skipMfg = mfgKey.isEmpty ||
        _isGeneric(mfg) ||
        mfgKey == 'google' ||
        mfgKey == 'android' ||
        rawModel.toLowerCase().contains(mfgKey);
    if (!skipMfg) {
      return _clip128('${_titleCaseWord(mfg)} $rawModel');
    }
    return _clip128(rawModel);
  }
  return fallback;
}

String platformFallbackDeviceName() {
  if (kIsWeb) return 'Web';
  try {
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iPhone';
    if (Platform.isMacOS) return 'Mac';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
  } catch (_) {}
  return 'Device';
}

/// Reads the OS model via native [getDeviceLabel]; never throws.
Future<String> readOsDeviceLabel({MethodChannel? channel}) async {
  final fallback = platformFallbackDeviceName();
  try {
    final raw = await (channel ?? kDeviceLabelChannel).invokeMethod<dynamic>(
      'getDeviceLabel',
    );
    if (raw is Map) {
      String? asString(Object? key) {
        final v = raw[key];
        return v == null ? null : v.toString();
      }

      return formatOsDeviceLabel(
        settingsName: asString('settingsName'),
        brand: asString('brand'),
        manufacturer: asString('manufacturer'),
        model: asString('model'),
        fallback: fallback,
      );
    }
  } catch (e) {
    debugPrint('device_label.read_failed: $e');
  }
  return fallback;
}
