import 'package:flutter/material.dart';

/// Бренд-цвета Teremok Connect — palette v3 «Дуб и мох» (2026-07-11).
///
/// Hex values live only here. Widget code must use [AppBrand] or
/// `Theme.of(context).colorScheme.*`, never raw `Color(0xFF…)`.
class AppBrand {
  AppBrand._();

  /// Oak — AppBar, primary CTA, active toggle.
  static const Color primary = Color(0xFF5D4037);

  /// Oak light — M3 primary containers.
  static const Color primaryContainer = Color(0xFF8D6E63);

  /// Moss — secondary accent, progress, active states.
  static const Color secondary = Color(0xFF558B2F);

  /// Honey amber — brand highlight (light / transient).
  static const Color accent = Color(0xFFFF8F00);

  /// Living House mustard (S1 mascot body) — glyph only, not UI chrome.
  static const Color livingHouse = Color(0xFFC78F29);

  /// Brightened honey for dark surfaces (WCAG AA on OLED).
  static const Color accentOnDark = Color(0xFFFFB300);

  /// Soft orange-50 wash behind Nest while connecting (not honey — avoids double-glow).
  static const Color connectingAura = Color(0xFFFFE0B2);

  /// Sage — connected / success.
  static const Color success = Color(0xFF2E7D32);

  /// Oak (not red) — disconnected / soft error (anti-pattern fix).
  static const Color error = Color(0xFF5D4037);

  /// Destructive actions (logout) — Telegram-style red, not soft oak error.
  static const Color destructive = Color(0xFFE53935);

  /// Honey — connecting / warning.
  static const Color warning = Color(0xFFFF8F00);

  /// Cream parchment — light theme surface.
  static const Color surfaceLight = Color(0xFFFAF8F3);

  /// Oak dark — dark theme surface.
  static const Color surfaceDark = Color(0xFF3E2723);

  /// Mid oak — dark cards / surface variant (lighter than surface for contrast).
  static const Color surfaceVariantDark = Color(0xFF5D4037);

  /// Forest — info chips (v3 token).
  static const Color info = Color(0xFF33691E);

  /// Readable subtitle / secondary text on dark oak surfaces.
  static const Color onSurfaceVariantDark = Color(0xFFE8DED6);

  static Color oakWithOpacity(double opacity) =>
      Color.fromRGBO(93, 64, 55, opacity);

  static Color mossWithOpacity(double opacity) =>
      Color.fromRGBO(85, 139, 47, opacity);
}

class AppTheme {
  AppTheme._();

  /// Светлая тема — Material 3, oak+moss.
  static final ThemeData light = _build(brightness: Brightness.light);

  /// Тёмная тема — Material 3, oak+moss.
  static final ThemeData dark = _build(brightness: Brightness.dark);

  static ThemeData _build({required Brightness brightness}) {
    final isDark = brightness == Brightness.dark;
    final surface = isDark ? AppBrand.surfaceDark : AppBrand.surfaceLight;
    final onSurface = isDark ? AppBrand.surfaceLight : AppBrand.surfaceDark;

    // Explicit brand overrides so ColorScheme.primary matches AppBrand.primary
    // (fromSeed alone shifts the tonal palette away from the seed hex).
    final scheme = ColorScheme.fromSeed(
      seedColor: AppBrand.primary,
      brightness: brightness,
      primary: AppBrand.primary,
      onPrimary: AppBrand.surfaceLight,
      primaryContainer: AppBrand.primaryContainer,
      onPrimaryContainer: AppBrand.surfaceDark,
      secondary: AppBrand.secondary,
      onSecondary: AppBrand.surfaceLight,
      // Dark: accentOnDark so connecting honey stays ≥4.5:1 on OLED.
      tertiary: isDark ? AppBrand.accentOnDark : AppBrand.accent,
      onTertiary: AppBrand.surfaceDark,
      error: AppBrand.error,
      onError: AppBrand.surfaceLight,
      surface: surface,
      onSurface: onSurface,
    ).copyWith(
      // Map AppBrand.info onto inversePrimary for info chips / badges.
      inversePrimary: AppBrand.info,
      surfaceContainerHighest:
          isDark ? AppBrand.surfaceVariantDark : AppBrand.primaryContainer,
      // Dark mode: warm light gray so Settings subtitles / card labels stay readable.
      onSurfaceVariant: isDark
          ? AppBrand.onSurfaceVariantDark
          : const Color(0xFF6D4C41),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: surface,
      iconTheme: IconThemeData(color: onSurface, size: 24),

      // === Typography ===
      textTheme: _buildTextTheme(scheme),

      // === AppBar ===
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
        scrolledUnderElevation: 4,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: scheme.onPrimary,
          fontSize: 22,
          fontWeight: FontWeight.w500,
        ),
        iconTheme: IconThemeData(color: scheme.onPrimary),
      ),

      // === FilledButton ===
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // === OutlinedButton ===
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          side: BorderSide(color: scheme.outline, width: 1.5),
        ),
      ),

      // === TextButton ===
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),

      // === Card ===
      // CardThemeData: required on Flutter 3.27+ (local 3.41 / CI bump).
      cardTheme: const CardThemeData(
        elevation: 2,
        margin: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),

      // === InputDecoration (TextField) ===
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        // withOpacity: CI Flutter 3.24; withValues is 3.27+.
        fillColor: scheme.surfaceContainerHighest.withOpacity(0.3),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),

      // === ProgressIndicator ===
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
      ),

      // === SnackBar ===
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),

      // === Divider ===
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 16,
      ),
    );
  }

  static TextTheme _buildTextTheme(ColorScheme scheme) {
    return TextTheme(
      displayLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w300,
        letterSpacing: -0.5,
        color: scheme.onSurface,
      ),
      displayMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w400,
        color: scheme.onSurface,
      ),
      headlineLarge: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      headlineMedium: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w500,
        color: scheme.onSurface,
      ),
      titleLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: scheme.onSurface,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: scheme.onSurface,
        height: 1.5,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: scheme.onSurfaceVariant,
        height: 1.4,
      ),
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      labelSmall: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w400,
        color: scheme.onSurfaceVariant,
      ),
    );
  }
}
