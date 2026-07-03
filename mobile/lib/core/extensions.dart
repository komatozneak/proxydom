import 'package:flutter/material.dart';

import 'theme.dart';

/// Brand-specific UI extensions.
extension BrandColors on ColorScheme {
  /// Цвет для VPN-статусов по строковому имени.
  Color vpnStatusColor(String status) {
    return switch (status) {
      'connected' => AppBrand.success,
      'connecting' => AppBrand.warning,
      'error' => AppBrand.error,
      _ => outline,
    };
  }
}