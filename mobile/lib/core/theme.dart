import 'package:flutter/material.dart';

/// Proxy Dom — monochrome mark harmony (charcoal + white + zinc).
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

  /// Moss — success / «Дуб» (semantic, not chrome accent).
  static const Color secondary = Color(0xFF558B2F);

  /// Chrome accent = charcoal (matches mono mark).
  static const Color accent = Color(0xFF1A1A1A);

  /// Living House mustard — Nest glyph only.
  static const Color livingHouse = Color(0xFFC78F29);

  /// Honey flame behind the house. Brighter than [livingHouse] so the roof edge stays visible.
  static const Color flame = Color(0xFFFF8F00);

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

  /// Free-client sheet: cream, lighter than the house so the roof stays separate.
  static const Color paperLight = Color(0xFFF6F1EA);

  /// Same hue as [paperLight], deepened so it stays oak rather than navy.
  static const Color paperDark = Color(0xFF221C1A);

  /// Ivory grid ink for the dark sheet. Drawn at low alpha so it does not cut type.
  static const Color paperGrid = Color(0xFFF4EDE3);

  /// Pencil grid on the light sheet. Darker than [paperLight].
  static const Color paperGridLight = Color(0xFFB7A898);

  /// Margin rule: living-house mustard mixed toward [destructive].
  static const Color paperMargin = Color(0xFFD4682E);

  /// Sky band behind refresh and the Telegram plane on a profile card.
  static const Color noticeBand = Color(0xFFC5EAF8);

  /// Same band on the dark sheet, deep enough for light icons.
  static const Color noticeBandDark = Color(0xFF1B4E63);

  /// Free slot in the harmony: the mid step of the same sky family, between
  /// [noticeBand] and [noticeBandDark]. Chrome fill for the refresh action —
  /// the cool counterweight to the moss paste button and the warm house.
  /// Charcoal ink stays readable on it (в‰€4.8:1) and the pill keeps its shape on
  /// both the charcoal ground and the cream sheet.
  static const Color actionSky = Color(0xFF3D8FB5);

  /// Free slot in the harmony: the amber step of the house gold, warmer than
  /// [livingHouse] and deeper than [flame]. Chrome fill for the QR action, so
  /// the bar keeps the house's own warmth instead of the borrowed notebook
  /// orange. Charcoal ink on it is в‰€5.9:1.
  static const Color actionAmber = Color(0xFFC98A16);

  /// Clay red for the delete ring. [destructive] is an alarm; this is that
  /// hue stepped toward the house ember, so the bin sits in the night instead
  /// of shouting over the name. The ring paints it at a low fill.
  static const Color actionClay = Color(0xFFC46256);

  /// Dark elevated cards — enough lift off [surfaceDark] so numbers read.
  static const Color surfaceVariantDark = Color(0xFF2C2C32);

  // ── The house in a cold night ──────────────────────────────────────────────
  //
  // The mascot is the reference: a warm ochre house with a charcoal aperture,
  // sampled straight off the mark. Everything warm in the app comes from it.
  // Everything the house stands on is cold — «тёплый дом в холодном интернете»
  // — so the gold reads as light rather than as a colour.

  /// House body. The brand colour, sampled off the mark.
  static const Color mascotGold = Color(0xFFC88F27);

  /// The lit top face of the house: same hue, one step up.
  static const Color mascotGoldLit = Color(0xFFE1AF49);

  /// The shaded side and the rim under the body.
  static const Color mascotGoldDeep = Color(0xFFA2701A);

  /// The warm halo the house throws into the dark — fireflies, glow, orbit.
  static const Color mascotEmber = Color(0xFFB4551B);

  /// Aperture: warm charcoal, not a neutral grey.
  static const Color mascotFace = Color(0xFF403F3C);

  /// Door and eyes.
  static const Color mascotCream = Color(0xFFF7F2E4);

  /// Fireflies: the small warm points that drift over the ground.
  static const Color firefly = Color(0xFFE8B94A);

  // ── One night, not two ─────────────────────────────────────────────────────
  //
  // The yard was blue-black, the rail green-black and the card a third grey:
  // three backgrounds that did not come from the same night. Now there is one
  // cold family with a green undertone — a forest at night. The rail is that
  // family one step down, the plates are that family with light on them, and
  // moss is an accent inside it, never a second ground.

  static const Color groundDark = Color(0xFF0D1211);

  static const Color groundDeep = Color(0xFF080B0A);

  static const Color forestDark = Color(0xFF0A100E);

  static const Color forestDeep = Color(0xFF070A09);

  static const Color forestShade = Color(0xFF040706);

  static const Color moss = Color(0xFF2F5238);

  /// Moss seen at night: the rail's selected plate, deep enough to sit under
  /// text instead of shouting over it.
  static const Color mossDeep = Color(0xFF1D3524);

  static const Color mossLight = Color(0xFF6E8F5C);

  /// The slab in daylight: pale stone, still damp, still green at the foot.
  static const Color stoneLight = Color(0xFFF0EDE6);

  static const Color stoneShade = Color(0xFFBDB6A8);

  /// Cards on the night ground: the same slate, lifted and warmed a hair, so a
  /// plate separates by light rather than only by value.
  static const Color surfaceRaisedDark = Color(0xFF171C1A);

  static const Color surfaceSunkDark = Color(0xFF101413);

  static const Color edgeDark = Color(0xFF353B47);

  static const Color edgeLight = Color(0xFFD8D3C6);

  static const Color shadowKeyDark = Color(0x7A000000);

  static const Color shadowKeyLight = Color(0x1F1A1A1A);

  /// White/black used only as a light or shade *source* when mixing surfaces —
  /// never as a fill on its own.
  static const Color lightSource = Color(0xFFFFFFFF);

  static const Color shadeSource = Color(0xFF000000);

  /// Motion. One spring for anything the finger drives, one ease for anything
  /// the screen does on its own.
  static const Duration motionPress = Duration(milliseconds: 120);

  static const Curve motionPressCurve = Curves.easeOutCubic;

  static const Duration motionReveal = Duration(milliseconds: 260);

  static const Curve motionRevealCurve = Curves.easeOutCubic;

  /// Unselected Material switch track in dark — lighter than card zinc.
  static const Color switchTrackOffDark = Color(0xFFB0B0B8);

  /// Thin rim on the unselected dark track so it does not melt into the card.
  static const Color switchTrackOutlineDark = Color(0xFFE4E4E7);

  // ── Text variants that pass 4.5:1 ────────────────────────────────────────
  //
  // The bright brand hues are light or glow: at 9–11 sp on paper the gold gave
  // 2.5:1, the moss 3.65:1 and the alarm red 3.76:1. These are the same hues
  // stepped down (or up on the night) until a small letter can sit in them.
  // Fills and status dots keep the bright values above.
  static const Color inkGoldLight = Color(0xFF7A4F00);
  static const Color inkGoldDark = Color(0xFFE1AF49);

  /// Moss as a letter. [moss] itself is the same value; the alias exists so a
  /// call site says "this is text", not "this is the success fill".
  static const Color inkMossLight = Color(0xFF2F5238);
  static const Color inkMossDark = Color(0xFF8FBF6A);

  static const Color inkDangerLight = Color(0xFFB3261E);
  static const Color inkDangerDark = Color(0xFFFF8A80);

  /// Switch on-track: the deep house gold in daylight, the lit gold at night.
  /// White on the light track is 3.84:1 (component threshold 3:1); the dark
  /// thumb is 8.64:1 on the night track.
  static const Color switchTrackOnLight = mascotGoldDeep;
  static const Color switchTrackOnDark = inkGoldDark;
  static const Color switchThumbOnDark = primary;

  /// Off track in daylight. The old track was lineLight on paper (~1.3:1),
  /// so every off switch in a list read as disabled rather than as a control.
  /// This is 3.4:1 against paper; the white thumb still stands out against it.
  static const Color switchTrackOffLight = Color(0xFF8F877E);

  static const Color surfaceElevatedLight = Color(0xFFFFFFFF);

  static const Color inkLight = Color(0xFF1A1A1A);
  static const Color inkMutedLight = Color(0xFF6B6B73);
  static const Color lineLight = Color(0xFFE4E4E7);

  static const Color inkDark = Color(0xFFF5F5F5);
  static const Color inkMutedDark = Color(0xFFC8C8D0);
  static const Color lineDark = Color(0xFF73737C);

  /// Hover on a window-caption button. The bar sits on the night, so the mark
  /// is a light wash rather than a fill — a filled chip reads as a button in an
  /// app and breaks the illusion that the caption is the window itself.
  static const Color hoverCaption = Color(0x1AFFFFFF);

  /// Painted under a caption button that is not hovered: nothing, explicitly.
  static const Color idleCaption = Color(0x00000000);

  /// Hover on the close button, which is the one button that carries an
  /// outcome rather than an action. Windows says that in red.
  static const Color hoverCloseCaption = Color(0xFFE81123);

  static const Color info = Color(0xFF558B2F);

  static const Color onSurfaceVariantDark = Color(0xFFC8C8D0);

  /// Free quota HP bar: healthy в†’ caution в†’ critical, then depleted grey.
  static const Color quotaHealthy = success;
  static const Color quotaCaution = livingHouse;
  static const Color quotaCritical = destructive;
  static const Color quotaDepleted = inkMutedLight;

  static const double radiusCard = 16;
  static const double radiusPill = 27;
  static const double radiusNavPill = 999;

  /// The line a tab starts on: its heading and its content share this gutter.
  ///
  /// It is a token because it was three numbers. The Servers heading sat at 44,
  /// Settings at 20 and Home at 24, so switching tabs shifted the page sideways
  /// under the eye — the heading looked pushed to the right on one screen and
  /// not on the next. A phone gets the narrow gutter, a window the wide one.
  static const double pageGutter = 24;
  static const double pageGutterWide = 32;

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
      fontFamily: 'Onest',
      fontFamilyFallback: const ['Inter'],
      iconTheme: IconThemeData(color: onSurface, size: 24),
      scrollbarTheme: ScrollbarThemeData(
        // The platform scrollbar is a wide grey slab that reads as chrome from
        // another app. A thin house-gold pill fades in only while scrolling and
        // sits just inside the edge instead of cutting the content.
        thickness: const WidgetStatePropertyAll(4),
        radius: const Radius.circular(2),
        crossAxisMargin: 3,
        mainAxisMargin: 6,
        thumbVisibility: const WidgetStatePropertyAll(false),
        trackVisibility: const WidgetStatePropertyAll(false),
        interactive: true,
        thumbColor: WidgetStateProperty.resolveWith((states) {
          final active = states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.dragged);
          final base =
              isDark ? AppBrand.mascotGoldLit : AppBrand.mascotGoldDeep;
          return base.withValues(alpha: active ? 0.78 : 0.42);
        }),
      ),
      textTheme: _buildTextTheme(scheme),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Onest',
          fontFamilyFallback: const ['Inter'],
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
          // The family has to be repeated here: a ButtonStyle textStyle
          // REPLACES the ambient default instead of merging with it, so without
          // it every button label silently falls back to the platform font and
          // the app ends up with two typefaces on one screen.
          textStyle: const TextStyle(
            fontFamily: 'Onest',
            fontFamilyFallback: const ['Inter'],
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: const StadiumBorder(),
          side: BorderSide(color: line, width: 1),
          textStyle: const TextStyle(
            fontFamily: 'Onest',
            fontFamilyFallback: const ['Inter'],
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: onSurface,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(
            fontFamily: 'Onest',
            fontFamilyFallback: const ['Inter'],
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
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
        thumbColor: WidgetStateProperty.resolveWith((s) {
          // On, the thumb is the plate against the house gold: white in
          // daylight, charcoal at night. Off, it stays the plain plate.
          if (s.contains(WidgetState.selected) && isDark) {
            return AppBrand.switchThumbOnDark;
          }
          return AppBrand.surfaceElevatedLight;
        }),
        trackColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) {
            // House gold, not moss: the switch is the same "on" as the house.
            // White on the light track is 3.84:1, the dark thumb 8.64:1.
            return isDark
                ? AppBrand.switchTrackOnDark
                : AppBrand.switchTrackOnLight;
          }
          return isDark ? AppBrand.switchTrackOffDark : AppBrand.inkMutedLight;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((s) {
          if (!isDark || s.contains(WidgetState.selected)) {
            return Colors.transparent;
          }
          return AppBrand.switchTrackOutlineDark;
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
        fontFamily: 'Onest',
        fontFamilyFallback: const ['Inter'],
        fontSize: 32,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        color: scheme.onSurface,
      ),
      displayMedium: TextStyle(
        fontFamily: 'Onest',
        fontFamilyFallback: const ['Inter'],
        fontSize: 28,
        fontWeight: FontWeight.w800,
        color: scheme.onSurface,
      ),
      headlineLarge: TextStyle(
        fontFamily: 'Onest',
        fontFamilyFallback: const ['Inter'],
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
      headlineMedium: TextStyle(
        fontFamily: 'Onest',
        fontFamilyFallback: const ['Inter'],
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
      titleLarge: TextStyle(
        fontFamily: 'Onest',
        fontFamilyFallback: const ['Inter'],
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
      titleMedium: TextStyle(
        fontFamily: 'Onest',
        fontFamilyFallback: const ['Inter'],
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
      bodyLarge: TextStyle(
        fontFamily: 'Onest',
        fontFamilyFallback: const ['Inter'],
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: scheme.onSurface,
        height: 1.45,
      ),
      bodyMedium: TextStyle(
        fontFamily: 'Onest',
        fontFamilyFallback: const ['Inter'],
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: scheme.onSurfaceVariant,
        height: 1.4,
      ),
      bodySmall: TextStyle(
        fontFamily: 'Onest',
        fontFamilyFallback: const ['Inter'],
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: scheme.onSurfaceVariant,
        height: 1.4,
      ),
      labelLarge: TextStyle(
        fontFamily: 'Onest',
        fontFamilyFallback: const ['Inter'],
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      labelMedium: TextStyle(
        fontFamily: 'Onest',
        fontFamilyFallback: const ['Inter'],
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      labelSmall: TextStyle(
        fontFamily: 'Onest',
        fontFamilyFallback: const ['Inter'],
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: scheme.onSurfaceVariant,
      ),
    );
  }
}
