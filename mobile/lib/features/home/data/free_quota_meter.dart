import 'package:flutter/material.dart';

import '../../../core/theme.dart';

/// Smooth HP-bar colour for Free remaining traffic (1 = full, 0 = empty).
///
/// Green → mustard → red while bytes drain. Grey only at exactly empty
/// («Трафик закончился»), not as a hard step at 20%.
Color freeQuotaBarColor(double remaining01) {
  final t = remaining01.clamp(0.0, 1.0);
  if (t <= 0) return AppBrand.quotaDepleted;
  if (t >= 0.5) {
    return Color.lerp(
      AppBrand.quotaCaution,
      AppBrand.quotaHealthy,
      (t - 0.5) / 0.5,
    )!;
  }
  return Color.lerp(
    AppBrand.quotaCritical,
    AppBrand.quotaCaution,
    t / 0.5,
  )!;
}
