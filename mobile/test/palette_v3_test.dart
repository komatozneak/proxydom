import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/core/theme.dart';
import 'package:proxydom/features/onboarding/presentation/onboarding_screen.dart';

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

  test('dark elevated cards lift off page surface', () {
    expect(_argb(AppBrand.surfaceDark), 0xFF121212);
    expect(_argb(AppBrand.surfaceVariantDark), isNot(0xFF121212));
    expect(_argb(AppBrand.surfaceVariantDark), isNot(0xFF1C1C1E));
    final dark = AppTheme.dark;
    expect(
      _argb(dark.colorScheme.surfaceContainerHighest),
      isNot(_argb(dark.colorScheme.surface)),
    );
    expect(_argb(dark.colorScheme.onSurface), 0xFFF5F5F5);
  });

  test('dark Switch track is not the card line', () {
    final dark = AppTheme.dark;
    final off = dark.switchTheme.trackColor!.resolve({});
    final on = dark.switchTheme.trackColor!.resolve({WidgetState.selected});
    expect(_argb(off!), isNot(_argb(dark.colorScheme.outline)));
    expect(_argb(off), isNot(_argb(dark.colorScheme.surfaceContainerHighest)));
    expect(_argb(on!), _argb(AppBrand.secondary));
  });

  test('dark muted labels and card outline lift off the card', () {
    expect(_argb(AppBrand.inkMutedDark), isNot(_argb(AppBrand.surfaceVariantDark)));
    expect(_argb(AppBrand.lineDark), isNot(_argb(AppBrand.surfaceVariantDark)));
    expect(_argb(AppBrand.lineDark), isNot(0xFF2A2A2E));
    final dark = AppTheme.dark;
    expect(
      _argb(dark.colorScheme.onSurfaceVariant),
      _argb(AppBrand.inkMutedDark),
    );
    expect(_argb(dark.colorScheme.outline), _argb(AppBrand.lineDark));
    expect(
      _argb(dark.colorScheme.outline),
      isNot(_argb(dark.colorScheme.surfaceContainerHighest)),
    );
  });

  test('dark Switch off-track and outline contrast against the card', () {
    final dark = AppTheme.dark;
    final off = dark.switchTheme.trackColor!.resolve({});
    final outline = dark.switchTheme.trackOutlineColor!.resolve({});
    final selectedOutline = dark.switchTheme.trackOutlineColor!.resolve({
      WidgetState.selected,
    });
    expect(_argb(off!), _argb(AppBrand.switchTrackOffDark));
    expect(_argb(off), isNot(_argb(AppBrand.surfaceVariantDark)));
    expect(_argb(off), isNot(0xFF6B6B73));
    expect(_argb(outline!), _argb(AppBrand.switchTrackOutlineDark));
    expect(_argb(selectedOutline!), 0x00000000);
  });

  test('dark onboarding glyph is not charcoal primary', () {
    final scheme = AppTheme.dark.colorScheme;
    expect(_argb(onboardingGlyphColor(scheme)), isNot(_argb(AppBrand.primary)));
    expect(_argb(onboardingGlyphColor(scheme)), _argb(scheme.onSurface));
    expect(_argb(onboardingInactiveDotColor(scheme)), _argb(scheme.outline));
  });

  test('mono theme still builds', () {
    final theme = AppTheme.light;
    expect(theme.brightness, Brightness.light);
    expect(theme.useMaterial3, true);
    expect(_argb(theme.colorScheme.surface), 0xFFF4F4F5);
    expect(_argb(theme.colorScheme.primary), 0xFF1A1A1A);
  });
}
