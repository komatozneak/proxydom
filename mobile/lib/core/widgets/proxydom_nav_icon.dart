import 'package:flutter/material.dart';

import 'app_icon.dart';

/// Center bottom-nav mark. Dark uses the plain house. Light uses the same
/// house with a charcoal contour so it does not disappear into the sheet.
///
/// Do not [ColorFilter] the asset (would crush tones).
/// Selected: full opacity; idle: muted. The selection ring lives on the button.
class ProxyDomNavIcon extends StatelessWidget {
  const ProxyDomNavIcon({
    super.key,
    this.selected = false,
    /// Side glyphs are ~20dp; mark should clearly dominate (~2.8×).
    this.size = 56,
  });

  final bool selected;
  final double size;

  static const _asset = 'assets/icon/logo_mark_nav.png';
  static const _assetLight = 'assets/icon/logo_mark_nav_light.png';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final light = theme.brightness == Brightness.light;
    final asset = light ? _assetLight : _asset;

    return AnimatedScale(
      // One size in both states. A selected bump pushes the rim through the
      // bar's top rule; selection is the ring color instead.
      scale: 1,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      child: AnimatedOpacity(
        opacity: selected ? 1.0 : 0.88,
        duration: const Duration(milliseconds: 180),
        child: SizedBox(
          width: size,
          height: size,
          child: Image.asset(
            asset,
            width: size,
            height: size,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            semanticLabel: 'DOM',
            errorBuilder: (_, __, ___) => AppIcon(
              selected ? AppIcons.houseFill : AppIcons.house,
              size: size * 0.72,
              color: selected
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
