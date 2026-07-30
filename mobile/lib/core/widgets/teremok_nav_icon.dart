import 'package:flutter/material.dart';

import 'app_icon.dart';

/// Center bottom-nav mark: baked monochrome Living House with «VPN» cutout.
///
/// Ogon-style: no «Home» caption — the word VPN *is* the tab identity.
/// Asset holes stay transparent under [ColorFilter] so letters punch through
/// the nav bar surface.
class TeremokNavIcon extends StatelessWidget {
  const TeremokNavIcon({
    super.key,
    this.selected = false,
    this.size = 40,
  });

  final bool selected;
  final double size;

  static const _asset = 'assets/icon/nav_vpn_teremok.png';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurfaceVariant;

    return SizedBox(
      width: size,
      height: size,
      child: ColorFiltered(
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
        child: Image.asset(
          _asset,
          width: size,
          height: size,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          errorBuilder: (_, __, ___) => AppIcon(
            selected ? AppIcons.houseFill : AppIcons.house,
            size: size * 0.9,
            color: color,
          ),
        ),
      ),
    );
  }
}
