import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/core/theme.dart';

void main() {
  test('v3 palette tokens exist', () {
    expect(AppBrand.primary.toARGB32(), 0xFF5D4037);
    expect(AppBrand.secondary.toARGB32(), 0xFF558B2F);
    expect(AppBrand.accent.toARGB32(), 0xFFFF8F00);
    expect(AppBrand.surfaceLight.toARGB32(), 0xFFFAF8F3);
    expect(AppBrand.surfaceDark.toARGB32(), 0xFF3E2723);
  });

  test('v3 theme still builds', () {
    final theme = AppTheme.light;
    expect(theme.brightness, Brightness.light);
    expect(theme.useMaterial3, true);
    expect(theme.colorScheme.primary.toARGB32(), 0xFF5D4037);
  });
}
