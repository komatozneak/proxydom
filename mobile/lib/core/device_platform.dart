import 'package:flutter/foundation.dart';

/// Wire value for register / recover / `/vpn/config` (`ios` / `android` / …).
///
/// Uses [defaultTargetPlatform] so widget tests can override the host OS.
String devicePlatformCode() {
  if (kIsWeb) return 'web';
  switch (defaultTargetPlatform) {
    case TargetPlatform.iOS:
      return 'ios';
    case TargetPlatform.android:
      return 'android';
    case TargetPlatform.macOS:
      return 'macos';
    case TargetPlatform.windows:
      return 'windows';
    case TargetPlatform.linux:
      return 'linux';
    case TargetPlatform.fuchsia:
      return 'fuchsia';
  }
}
