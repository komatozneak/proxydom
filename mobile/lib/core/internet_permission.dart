import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// MethodChannel shared with VPN native (see [VpnChannelRegistry]).
const MethodChannel kInternetPermissionChannel = MethodChannel('proxydom/vpn');

/// Android 17 treats [INTERNET] as a dangerous runtime permission on Pixel.
/// Missing grant → Dart sockets fail with errno 13 (EACCES) even when Chrome
/// has network. Await this before API discovery / anonymous register.
Future<bool> ensureInternetPermissionGranted({
  MethodChannel? channel,
  bool? isAndroid,
}) async {
  if (kIsWeb) return true;
  final android = isAndroid ?? _platformIsAndroid();
  if (!android) return true;
  try {
    final granted = await (channel ?? kInternetPermissionChannel)
        .invokeMethod<bool>('ensureInternetPermission');
    // null = older APK / test mock without the method — do not block bootstrap.
    return granted != false;
  } on MissingPluginException {
    return true;
  } catch (e) {
    debugPrint('internet.ensure_failed: $e');
    return true;
  }
}

/// Route Dart sockets via Wi‑Fi/LTE, not a leftover tun0.
///
/// Native Hy2 uses [VpnService.protect]; Dio does not. While TUN / lockdown
/// is up, unprotected connect to the API IP fails with errno 13.
Future<bool> bindProcessToUnderlyingNetwork({
  MethodChannel? channel,
  bool? isAndroid,
}) async {
  if (kIsWeb) return true;
  final android = isAndroid ?? _platformIsAndroid();
  if (!android) return true;
  try {
    final ok = await (channel ?? kInternetPermissionChannel)
        .invokeMethod<bool>('bindToUnderlyingNetwork');
    return ok != false;
  } on MissingPluginException {
    return true;
  } catch (e) {
    debugPrint('internet.bind_underlying_failed: $e');
    return true;
  }
}

bool _platformIsAndroid() {
  try {
    return Platform.isAndroid;
  } catch (_) {
    return false;
  }
}
