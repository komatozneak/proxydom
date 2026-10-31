import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme.dart';
import 'app_icon.dart';

/// Full-bleed location mark (flag as the icon background).
///
/// Country codes use flag SVGs. Node categories use neutral Phosphor tiles,
/// not third-party service marks.
class LocationFlagIcon extends StatelessWidget {
  const LocationFlagIcon({
    super.key,
    required this.flag,
    this.size = 48,
    this.borderRadius,
  });

  /// Emoji (`🇷🇺`), short key (`ru`, `media`, `cloud`), or ISO code.
  final String flag;
  final double size;
  final double? borderRadius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final key = locationFlagKey(flag);
    final radius = borderRadius ?? (size * 0.28).clamp(8.0, 16.0);
    final product = isCategoryFlagKey(key);
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
                    color: _tileForeground(theme, key),
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

/// True for the neutral category keys a node card can carry.
bool isCategoryFlagKey(String key) =>
    key == 'media' || key == 'cloud' || key == 'work' || key == 'backup';

/// Known emoji → ISO / category key. Anything else is passed through as
/// lowercase. A legacy `gaming` value stays readable so an old stored node
/// keeps a mark after the rename.
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
      return 'cloud';
    case '👑':
      return 'media';
  }
  final lower = t.toLowerCase();
  if (lower == 'usa') return 'us';
  if (lower == 'eu') return 'lv';
  if (lower == 'gaming') return 'cloud';
  return lower;
}

/// Asset path for a country flag (flag-icons / FlagKit-compatible ISO file).
String? locationFlagAsset(String key) {
  if (isCategoryFlagKey(key)) return null;
  if (key.length == 2 || key.contains('-')) {
    return 'assets/flags/$key.svg';
  }
  return null;
}

IconData _tileIcon(String key) {
  return switch (key) {
    'media' => AppIcons.categoryMedia,
    'cloud' => AppIcons.categoryCloud,
    'work' => AppIcons.categoryWork,
    'backup' => AppIcons.categoryBackup,
    _ => AppIcons.globe,
  };
}

Color _tileColor(ThemeData theme, String key) {
  return switch (key) {
    'media' => AppBrand.mascotGoldDeep,
    'cloud' => AppBrand.secondary,
    'work' => AppBrand.moss,
    _ => theme.colorScheme.surfaceContainerHighest,
  };
}

Color _tileForeground(ThemeData theme, String key) {
  return switch (key) {
    'media' || 'cloud' || 'work' => AppBrand.mascotCream,
    _ => theme.colorScheme.onSurface.withValues(alpha: 0.62),
  };
}
