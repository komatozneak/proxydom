import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../data/subscription_label.dart';

/// Rounded tile for a node: a neutral category mark or a country flag.
class PoolServerMark extends StatelessWidget {
  const PoolServerMark({super.key, required this.label});

  final PoolServerLabel label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (color, icon, foreground) = switch (label.tile) {
      PoolTile.media => (
          AppBrand.mascotGoldDeep,
          AppIcons.categoryMedia,
          AppBrand.mascotCream,
        ),
      PoolTile.cloud => (
          AppBrand.secondary,
          AppIcons.categoryCloud,
          AppBrand.mascotCream,
        ),
      PoolTile.work => (
          AppBrand.moss,
          AppIcons.categoryWork,
          AppBrand.mascotCream,
        ),
      PoolTile.backup => (
          theme.colorScheme.surfaceContainerHighest,
          AppIcons.categoryBackup,
          theme.colorScheme.onSurface.withValues(alpha: 0.62),
        ),
      PoolTile.flag => (
          theme.colorScheme.surfaceContainerHighest,
          AppIcons.globe,
          theme.colorScheme.onSurface,
        ),
    };
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: label.tile == PoolTile.flag && label.flag.isNotEmpty
          ? Text(label.flag, style: const TextStyle(fontSize: 22))
          : AppIcon(icon, size: 20, color: foreground),
    );
  }
}
