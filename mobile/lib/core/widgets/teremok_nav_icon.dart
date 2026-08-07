import 'package:flutter/material.dart';

import 'app_icon.dart';

/// Center bottom-nav mark: monochrome Living House circle with «VPN» cutout.
///
/// Asset is already charcoal/white — do not [ColorFilter] it (would crush tones).
/// Selected: full opacity + slight scale; idle: muted.
class TeremokNavIcon extends StatelessWidget {
  const TeremokNavIcon({
    super.key,
    this.selected = false,
    /// Side glyphs are ~20dp; mark should clearly dominate (~2.8×).
    this.size = 56,
  });

  final bool selected;
  final double size;

  static const _asset = 'assets/icon/logo_mark_nav.png';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedScale(
      // Idle stays close to selected — both states read “larger than side tabs”.
      scale: selected ? 1.0 : 0.96,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      child: AnimatedOpacity(
        opacity: selected ? 1.0 : 0.88,
        duration: const Duration(milliseconds: 180),
        child: SizedBox(
          width: size,
          height: size,
          child: Image.asset(
            _asset,
            width: size,
            height: size,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            semanticLabel: 'VPN',
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
