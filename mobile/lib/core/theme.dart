import 'package:flutter/material.dart';

/// Teremok VPN — monochrome mark harmony (charcoal + white + zinc).
///
/// Hex values live only here. Widget code must use [AppBrand] or
/// `Theme.of(context).colorScheme.*`, never raw `Color(0xFF…)`.
///
/// Typeface: Inter (rsms/inter, SIL OFL) bundled in `assets/fonts/`.
///
/// [livingHouse] is Nest/glyph only — not UI chrome.
class AppBrand {
  AppBrand._();

  /// Charcoal — primary chrome / mark circle (#1A1A1A).
  static const Color primary = Color(0xFF1A1A1A);

  static const Color primaryContainer = Color(0xFF2A2A2E);

  /// Moss — success / «работает» (semantic, not chrome accent).
  static const Color secondary = Color(0xFF558B2F);

  /// Chrome accent = charcoal (matches mono mark).
  static const Color accent = Color(0xFF1A1A1A);

  /// Living House mustard — Nest glyph only.
  static const Color livingHouse = Color(0xFFC78F29);

  /// Accent on dark surfaces — near-white.
  static const Color accentOnDark = Color(0xFFF5F5F5);

  /// Soft charcoal wash (selected / connecting aura).
  static const Color connectingAura = Color(0x261A1A1A);

  static const Color honeySurface = Color(0xFFECECED);

  static const Color success = Color(0xFF558B2F);

  static const Color error = Color(0xFF1A1A1A);

  static const Color destructive = Color(0xFFE53935);

  /// Connecting / in-progress — muted zinc (mono chrome).
  static const Color warning = Color(0xFF6B6B73);

  /// Caution / partial setup — Living House mustard (Nest glyph family).
  static const Color caution = livingHouse;

  static const Color surfaceLight = Color(0xFFF4F4F5);

  static const Color surfaceDark = Color(0xFF121212);

  /// Dark elevated — near mark charcoal family.
  static const Color surfaceVariantDark = Color(0xFF1C1C1E);

  static const Color surfaceElevatedLight = Color(0xFFFFFFFF);

  static const Color inkLight = Color(0xFF1A1A1A);
  static const Color inkMutedLight = Color(0xFF6B6B73);
  static const Color lineLight = Color(0xFFE4E4E7);

  static const Color inkDark = Color(0xFFF5F5F5);
  static const Color inkMutedDark = Color(0xFFA1A1AA);
  static const Color lineDark = Color(0xFF2A2A2E);

  static const Color info = Color(0xFF558B2F);

  static const Color onSurfaceVariantDark = Color(0xFFA1A1AA);

  /// Free quota HP bar: healthy → caution → critical, then depleted grey.
  static const Color quotaHealthy = success;
  static const Color quotaCaution = livingHouse;
  static const Color quotaCritical = destructive;
  static const Color quotaDepleted = inkMutedLight;

  static const double radiusCard = 16;
  static const double radiusPill = 27;
  static const double radiusNavPill = 999;

  static Color oakWithOpacity(double opacity) =>
      Color.fromRGBO(26, 26, 26, opacity);

  static Color mossWithOpacity(double opacity) =>
      Color.fromRGBO(85, 139, 47, opacity);

  /// Soft charcoal wash (legacy name kept for call sites).
  static Color honeyWithOpacity(double opacity) =>
      Color.fromRGBO(26, 26, 26, opacity);

  static Color inkWithOpacity(double opacity) =>
      Color.fromRGBO(26, 26, 26, opacity);
}

class AppTheme {
  AppTheme._();

  static final ThemeData light = _build(brightness: Brightness.light);
  static final ThemeData dark = _build(brightness: Brightness.dark);

  static ThemeData _build({required Brightness brightness}) {
    final isDark = brightness == Brightness.dark;
    final bg = isDark ? AppBrand.surfaceDark : AppBrand.surfaceLight;
    final elevated =
        isDark ? AppBrand.surfaceVariantDark : AppBrand.surfaceElevatedLight;
    final onSurface = isDark ? AppBrand.inkDark : AppBrand.inkLight;
    final muted = isDark ? AppBrand.inkMutedDark : AppBrand.inkMutedLight;
    final line = isDark ? AppBrand.lineDark : AppBrand.lineLight;
    final chrome = isDark ? AppBrand.accentOnDark : AppBrand.primary;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: chrome,
      onPrimary: isDark ? AppBrand.primary : AppBrand.surfaceElevatedLight,
      primaryContainer:
          isDark ? AppBrand.primaryContainer : AppBrand.honeySurface,
      onPrimaryContainer: AppBrand.primary,
      secondary: AppBrand.secondary,
      onSecondary: AppBrand.surfaceElevatedLight,
      tertiary: chrome,
      onTertiary: isDark ? AppBrand.primary : AppBrand.surfaceElevatedLight,
      error: AppBrand.destructive,
      onError: AppBrand.surfaceElevatedLight,
      surface: bg,
      onSurface: onSurface,
      surfaceContainerHighest: elevated,
      onSurfaceVariant: muted,
      outline: line,
      outlineVariant: line,
      inversePrimary: AppBrand.info,
      shadow: Colors.black.withValues(alpha: 0.08),
      scrim: Colors.black54,
      inverseSurface: onSurface,
      onInverseSurface: bg,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      fontFamily: 'Inter',
      iconTheme: IconThemeData(color: onSurface, size: 24),
      textTheme: _buildTextTheme(scheme),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          color: onSurface,
          fontSize: 28,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
        ),
        iconTheme: IconThemeData(color: onSurface),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: elevated,
        indicatorColor: AppBrand.inkWithOpacity(0.08),
        elevation: 0,
        height: 72,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            color: selected ? onSurface : muted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 20,
            color: selected ? onSurface : muted,
          );
        }),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: chrome,
          foregroundColor:
              isDark ? AppBrand.primary : AppBrand.surfaceElevatedLight,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: const StadiumBorder(),
          side: BorderSide(color: line, width: 1),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: onSurface,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: const StadiumBorder(),
        ),
      ),
      cardTheme: CardThemeData(
        color: elevated,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppBrand.radiusCard),
          side: BorderSide(color: line),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => AppBrand.surfaceElevatedLight,
        ),
        trackColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) return chrome;
          return line;
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? AppBrand.surfaceVariantDark : AppBrand.surfaceLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: chrome, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: chrome,
        linearTrackColor: line,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: line,
        thickness: 1,
        space: 1,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: muted,
        textColor: onSurface,
      ),
    );
  }

  static TextTheme _buildTextTheme(ColorScheme scheme) {
    return TextTheme(
      displayLarge: TextStyle(
        fontFamily: 'Inter',
        fontSize: 32,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        color: scheme.onSurface,
      ),
      displayMedium: TextStyle(
        fontFamily: 'Inter',
        fontSize: 28,
        fontWeight: FontWeight.w800,
        color: scheme.onSurface,
      ),
      headlineLarge: TextStyle(
        fontFamily: 'Inter',
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
      headlineMedium: TextStyle(
        fontFamily: 'Inter',
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
      titleLarge: TextStyle(
        fontFamily: 'Inter',
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
      titleMedium: TextStyle(
        fontFamily: 'Inter',
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      bodyLarge: TextStyle(
        fontFamily: 'Inter',
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: scheme.onSurface,
        height: 1.5,
      ),
      bodyMedium: TextStyle(
        fontFamily: 'Inter',
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: scheme.onSurfaceVariant,
        height: 1.4,
      ),
      labelLarge: TextStyle(
        fontFamily: 'Inter',
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      labelSmall: TextStyle(
        fontFamily: 'Inter',
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: scheme.onSurfaceVariant,
      ),
    );
  }
}
