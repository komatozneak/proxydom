import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/core/theme.dart';

int _argb(Color c) {
  try {
    // ignore: avoid_dynamic_calls
    return (c as dynamic).toARGB32() as int;
  } catch (_) {
    // ignore: deprecated_member_use
    return c.value;
  }
}

void main() {
  test('mono mark charcoal+zinc palette tokens', () {
    expect(_argb(AppBrand.primary), 0xFF1A1A1A);
    expect(_argb(AppBrand.accent), 0xFF1A1A1A);
    expect(_argb(AppBrand.secondary), 0xFF558B2F);
    expect(_argb(AppBrand.surfaceLight), 0xFFF4F4F5);
    expect(_argb(AppBrand.surfaceDark), 0xFF121212);
    expect(_argb(AppBrand.livingHouse), 0xFFC78F29);
  });

  test('mono theme still builds', () {
    final theme = AppTheme.light;
    expect(theme.brightness, Brightness.light);
    expect(theme.useMaterial3, true);
    expect(_argb(theme.colorScheme.surface), 0xFFF4F4F5);
    expect(_argb(theme.colorScheme.primary), 0xFF1A1A1A);
  });
}
