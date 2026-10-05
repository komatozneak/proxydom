import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/interaction.dart';
import '../../../core/widgets/terminal_type.dart';
import '../data/subscription_label.dart';
import 'server_glyph.dart';

/// The house gold that reads as ink on this brightness.
///
/// The mark's own gold is a light on a night, so it is only ever a fill or a
/// glow. Set as type on paper it turns to mud: this is the deeper step of the
/// same hue, the one a letter can sit in.
Color goldInk(BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return dark ? AppBrand.mascotGoldLit : AppBrand.mascotGoldDeep;
}

/// One node in the pool, drawn as a line on an instrument panel rather than as
/// a list row: a mark, the name, where it lives, and the protocol.
///
/// Every node used to be its own bordered card inside the profile card — a box
/// inside a box, with a rounded frame and a hairline, four of them stacked. The
/// profile is already a plate, so the lines inside it are ruled: the mark and
/// the name say what a row is, and a printed rule says where it ends.
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
    final gold = goldInk(context);
    final subtitle = label.subtitle.isEmpty ? endpoint : label.subtitle;

    return HoverBuilder(
      onTap: onTap,
      builder: (context, hover) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          color: selected
              ? gold.withValues(alpha: dark ? 0.13 : 0.10)
              : (hover
                  ? theme.colorScheme.onSurface.withValues(alpha: 0.04)
                  : Colors.transparent),
          // The chosen line wears an edge, not a frame. A second outline around
          // the row would say "button" once per node on one card, and the plate
          // already carries an edge of its own.
          child: Stack(
            children: [
              if (selected)
                const Positioned(
                  left: 0,
                  top: 8,
                  bottom: 8,
                  width: 2.5,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppBrand.mascotGold,
                      borderRadius: BorderRadius.horizontal(
                        right: Radius.circular(2),
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
                child: Row(
                  children: [
                    ServerGlyph(label: label, size: 32),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            label.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5,
                              height: 1.25,
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
                    // The protocol is the one fact a person deploying through
                    // this app checks first; Hy2 is the only one that can dial.
                    // A wash of the house gold, not another outlined box.
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppBrand.mascotGold.withValues(
                          alpha: dark ? 0.16 : 0.13,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'HY2',
                        style: terminalText(
                          context,
                          size: 9.5,
                          color: gold,
                          weight: 700,
                          spacing: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The hairline between two lines of a pool.
///
/// Inset past the mark so every name in the card sits on one line, and printed
/// in shade rather than drawn in outline: a rule is a mark on the plate, a
/// border is a box around it.
class NodeRule extends StatelessWidget {
  const NodeRule({super.key});

  /// Left edge of the text column of a [NodeLine]: 14 + 32 + 12.
  static const double inset = 58;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(left: inset),
      child: Container(
        height: 1,
        color: dark
            ? AppBrand.lightSource.withValues(alpha: 0.06)
            : AppBrand.shadeSource.withValues(alpha: 0.07),
      ),
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
    this.dense = false,
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

  /// A key that lives inside a card instead of on a bar.
  ///
  /// At 44px with a full border the seller's Telegram key was the loudest
  /// object on the profile — taller than the name it belongs to, and framed on
  /// every side. A key inside a note answers to the note.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final enabled = onTap != null && !busy;
    final height = compact ? 34.0 : (dense ? 34.0 : 44.0);

    Widget paint(bool hover) {
      final (Color ink, Color edge, Color fill) = switch (tone) {
        AppActionTone.primary => (
            theme.colorScheme.onPrimary,
            AppBrand.mascotGold,
            AppBrand.mascotGold,
          ),
        AppActionTone.link => (
            theme.colorScheme.onSurface,
            AppBrand.actionSky.withValues(alpha: dense ? 0.40 : 0.55),
            AppBrand.actionSky.withValues(alpha: dense ? 0.09 : 0.12),
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
        height: height,
        width: compact ? 34 : null,
        padding: compact
            ? EdgeInsets.zero
            : EdgeInsets.symmetric(horizontal: dense ? 11 : 14),
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
              AppIcon(icon, size: compact ? 16 : (dense ? 15 : 17), color: ink),
            if (!compact) ...[
              SizedBox(width: dense ? 7 : 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: dense ? 12.5 : 13,
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
