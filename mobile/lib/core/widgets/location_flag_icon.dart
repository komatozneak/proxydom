import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../theme.dart';
import 'app_icon.dart';

/// Full-bleed location mark (Hiddify-style flag as the icon background).
///
/// Country codes use flag-icons SVGs. YouTube / gaming are colored Phosphor
/// tiles (MIT), not monochrome SVG silhouettes.
class LocationFlagIcon extends StatelessWidget {
  const LocationFlagIcon({
    super.key,
    required this.flag,
    this.size = 48,
    this.borderRadius,
  });

  /// Emoji (`🇺🇸`), short key (`us`, `lv`, `gaming`), or ISO code.
  final String flag;
  final double size;
  final double? borderRadius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final key = locationFlagKey(flag);
    final radius = borderRadius ?? (size * 0.28).clamp(8.0, 16.0);
    final product = key == 'youtube' || key == 'gaming';
    final asset = product ? null : locationFlagAsset(key);

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: product
            ? ColoredBox(
                color: _tileColor(theme, key),
                child: Center(
                  child: AppIcon(
                    _tileIcon(key),
                    size: size * 0.55,
                    color: Colors.white,
                  ),
                ),
              )
            : asset != null
                ? SvgPicture.asset(
                    asset,
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                  )
                : ColoredBox(
                    color: theme.colorScheme.primary,
                    child: Center(
                      child: AppIcon(
                        AppIcons.globe,
                        size: size * 0.52,
                        color: theme.colorScheme.onPrimary,
                      ),
                    ),
                  ),
      ),
    );
  }
}

/// Known emoji → ISO / tile key. Anything else is passed through as lowercase.
String locationFlagKey(String flag) {
  final t = flag.trim();
  if (t.isEmpty || t == '🌐' || t == '🌍') return 'lv';
  switch (t) {
    case '🇺🇸':
      return 'us';
    case '🇱🇻':
      return 'lv';
    case '🇮🇳':
      return 'in';
    case '🇳🇱':
      return 'nl';
    case '🇩🇪':
      return 'de';
    case '🎮':
      return 'gaming';
    case '👑':
      return 'youtube';
  }
  final lower = t.toLowerCase();
  if (lower == 'usa') return 'us';
  if (lower == 'eu') return 'lv';
  return lower;
}

/// Asset path for a country flag (flag-icons / FlagKit-compatible ISO file).
String? locationFlagAsset(String key) {
  if (key == 'gaming' || key == 'youtube') return null;
  if (key.length == 2 || key.contains('-')) {
    return 'assets/flags/$key.svg';
  }
  return null;
}

IconData _tileIcon(String key) {
  if (key == 'youtube') return PhosphorIconsFill.youtubeLogo;
  if (key == 'gaming') return PhosphorIconsFill.gameController;
  return AppIcons.globe;
}

Color _tileColor(ThemeData theme, String key) {
  if (key == 'youtube') return AppBrand.destructive;
  if (key == 'gaming') return AppBrand.secondary;
  return theme.colorScheme.primary;
}
