import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Brand-tinted icon wrapper. Prefer static [PhosphorIconsRegular] / Fill icons
/// so Flutter tree-shakes unused glyphs (never build dynamic [IconData] codes).
class AppIcon extends StatelessWidget {
  const AppIcon(
    this.icon, {
    super.key,
    this.size = 24,
    this.color,
    this.semanticLabel,
  });

  final IconData icon;
  final double size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PhosphorIcon(
      icon,
      size: size,
      color: color ?? theme.iconTheme.color ?? theme.colorScheme.onSurface,
      semanticLabel: semanticLabel,
    );
  }
}

/// Canonical Phosphor set for Teremok UI (regular weight).
abstract final class AppIcons {
  static const IconData power = PhosphorIconsRegular.power;
  static const IconData shield = PhosphorIconsRegular.shield;
  static const IconData warning = PhosphorIconsRegular.warningCircle;
  static const IconData play = PhosphorIconsRegular.play;
  static const IconData stop = PhosphorIconsRegular.stop;
  static const IconData refresh = PhosphorIconsRegular.arrowsClockwise;
  static const IconData hourglass = PhosphorIconsRegular.hourglass;
  static const IconData servers = PhosphorIconsRegular.hardDrives;
  static const IconData settings = PhosphorIconsRegular.gearSix;
  static const IconData info = PhosphorIconsRegular.info;
  static const IconData logout = PhosphorIconsRegular.signOut;
  static const IconData back = PhosphorIconsRegular.arrowLeft;
  static const IconData download = PhosphorIconsRegular.cloudArrowDown;
}
