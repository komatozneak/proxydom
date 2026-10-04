import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/interaction.dart';
import '../data/subscription_label.dart';
import 'server_glyph.dart';

/// One node in the pool, drawn like a line on an instrument panel rather than
/// like a list row: a mark, the name, where it lives, and the protocol.
class NodeLine extends StatelessWidget {
  const NodeLine({
    super.key,
    required this.label,
    required this.endpoint,
    required this.selected,
    required this.onTap,
  });

  final PoolServerLabel label;
  final String endpoint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final mute = dark ? AppBrand.inkMutedDark : AppBrand.inkMutedLight;
    final subtitle = label.subtitle.isEmpty ? endpoint : label.subtitle;

    return HoverBuilder(
      onTap: onTap,
      builder: (context, hover) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? AppBrand.mascotGold.withValues(alpha: 0.10)
                : (hover
                      ? theme.colorScheme.onSurface.withValues(alpha: 0.04)
                      : Colors.transparent),
            borderRadius: BorderRadius.circular(AppBrand.radiusCard),
            border: Border.all(
              color: selected
                  ? AppBrand.mascotGold.withValues(alpha: 0.45)
                  : theme.colorScheme.outline.withValues(alpha: 0.55),
            ),
          ),
          child: Row(
            children: [
              ServerGlyph(label: label, size: 34),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: mute,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // The protocol is the one fact a person deploying through this app
              // checks first; Hy2 is the only one that can dial.
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: AppBrand.mascotGold.withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  'HY2',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                    color: AppBrand.mascotGoldLit,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// One action, standing on its own.
///
/// The old card crammed share, refresh, the seller link and the trash into one
/// corner of coloured squares. These are either a labelled key or РІР‚вЂќ when
/// [compact] is set РІР‚вЂќ a square with a tooltip, for the row beside the profile
/// name where a word would crowd the name out.
class ToolAction extends StatelessWidget {
  const ToolAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.tooltip,
    this.tone = AppActionTone.neutral,
    this.busy = false,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  /// Tooltip text for the compact form, where the label is not painted.
  final String? tooltip;
  final AppActionTone tone;
  final bool busy;

  /// Icon only: a square beside the profile name.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final enabled = onTap != null && !busy;

    Widget paint(bool hover) {
      final (Color ink, Color edge, Color fill) = switch (tone) {
      AppActionTone.primary => (
          theme.colorScheme.onPrimary,
          AppBrand.mascotGold,
          AppBrand.mascotGold,
        ),
      AppActionTone.link => (
          theme.colorScheme.onSurface,
          AppBrand.actionSky.withValues(alpha: 0.55),
          AppBrand.actionSky.withValues(alpha: 0.12),
        ),
      AppActionTone.danger => (
          theme.colorScheme.onSurface,
          theme.colorScheme.error.withValues(alpha: 0.45),
          theme.colorScheme.error.withValues(alpha: 0.08),
        ),
      AppActionTone.neutral => (
          dark ? AppBrand.inkDark : AppBrand.inkLight,
          theme.colorScheme.outline,
          theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        ),
    };

    return Container(
        height: compact ? 34 : 44,
        width: compact ? 34 : null,
        padding: compact
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(horizontal: 14),
        alignment: compact ? Alignment.center : null,
        decoration: BoxDecoration(
          color: hover && enabled
              ? Color.alphaBlend(ink.withValues(alpha: 0.08), fill)
              : fill,
          borderRadius: BorderRadius.circular(AppBrand.radiusCard),
          border: Border.all(color: edge),
        ),
        child: Row(
          // Always shrink-wrap: these sit in Rows that hand their children an
          // unbounded width, and a max-size Row with a Flexible child throws
          // there.
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: ink),
              )
            else
              AppIcon(icon, size: compact ? 16 : 17, color: ink),
            if (!compact) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                    color: ink,
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return HoverBuilder(
      onTap: enabled ? onTap : null,
      builder: (context, hover) {
        final child = AnimatedOpacity(
          duration: const Duration(milliseconds: 140),
          opacity: enabled ? 1.0 : 0.45,
          child: paint(hover),
        );
        final named = tooltip ?? label;
        if (compact || named == label) return child;
        return Tooltip(message: named, child: child);
      },
    );
  }
}

enum AppActionTone { primary, link, danger, neutral }