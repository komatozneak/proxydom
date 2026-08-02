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
  static const IconData shieldCheck = PhosphorIconsRegular.shieldCheck;
  static const IconData warning = PhosphorIconsRegular.warningCircle;
  static const IconData play = PhosphorIconsRegular.play;
  static const IconData stop = PhosphorIconsRegular.stop;
  static const IconData refresh = PhosphorIconsRegular.arrowsClockwise;
  static const IconData hourglass = PhosphorIconsRegular.hourglass;
  static const IconData servers = PhosphorIconsRegular.hardDrives;
  static const IconData settings = PhosphorIconsRegular.gearSix;
  static const IconData gear = PhosphorIconsRegular.gear;
  static const IconData info = PhosphorIconsRegular.info;
  static const IconData question = PhosphorIconsRegular.question;
  static const IconData logout = PhosphorIconsRegular.signOut;
  static const IconData back = PhosphorIconsRegular.arrowLeft;
  static const IconData download = PhosphorIconsRegular.cloudArrowDown;
  static const IconData upload = PhosphorIconsRegular.cloudArrowUp;
  static const IconData globe = PhosphorIconsRegular.globe;
  static const IconData globeHemisphereWest =
      PhosphorIconsRegular.globeHemisphereWest;
  static const IconData gauge = PhosphorIconsRegular.gauge;
  static const IconData phone = PhosphorIconsRegular.phone;
  static const IconData devices = PhosphorIconsRegular.devices;
  static const IconData crown = PhosphorIconsRegular.crown;
  static const IconData sliders = PhosphorIconsRegular.sliders;
  static const IconData moon = PhosphorIconsRegular.moon;
  static const IconData bug = PhosphorIconsRegular.bug;
  static const IconData notifications = PhosphorIconsRegular.bell;
  static const IconData chevronRight = PhosphorIconsRegular.caretRight;
  static const IconData search = PhosphorIconsRegular.magnifyingGlass;
  static const IconData plus = PhosphorIconsRegular.plus;
  static const IconData trash = PhosphorIconsRegular.trash;
  static const IconData tree = PhosphorIconsRegular.tree;
  static const IconData treeFill = PhosphorIconsFill.tree;
  static const IconData house = PhosphorIconsRegular.house;
  static const IconData houseFill = PhosphorIconsFill.house;
  static const IconData check = PhosphorIconsRegular.check;
  static const IconData checkCircle = PhosphorIconsRegular.checkCircle;
  static const IconData checkCircleFill = PhosphorIconsFill.checkCircle;
  static const IconData x = PhosphorIconsRegular.x;
  static const IconData xCircle = PhosphorIconsRegular.xCircle;
  static const IconData xCircleFill = PhosphorIconsFill.xCircle;
}
