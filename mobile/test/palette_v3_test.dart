import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/core/theme.dart';

int _argb(Color c) {
  // Flutter 3.27+: toARGB32(); CI 3.24: Color.value.
  try {
    // ignore: avoid_dynamic_calls
    return (c as dynamic).toARGB32() as int;
  } catch (_) {
    // ignore: deprecated_member_use
    return c.value;
  }
}

void main() {
  test('v3 palette tokens exist', () {
    expect(_argb(AppBrand.primary), 0xFF5D4037);
    expect(_argb(AppBrand.secondary), 0xFF558B2F);
    expect(_argb(AppBrand.accent), 0xFFFF8F00);
    expect(_argb(AppBrand.surfaceLight), 0xFFFAF8F3);
    expect(_argb(AppBrand.surfaceDark), 0xFF3E2723);
  });

  test('v3 theme still builds', () {
    final theme = AppTheme.light;
    expect(theme.brightness, Brightness.light);
    expect(theme.useMaterial3, true);
    expect(_argb(theme.colorScheme.primary), 0xFF5D4037);
  });
}
