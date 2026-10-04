import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_surface.dart';
import '../../../l10n/app_localizations.dart';
import '../data/subscription_traffic.dart';
import 'server_instrument_parts.dart';

/// A bought profile, drawn as an instrument.
///
/// The old card was a coloured slab with four square icons in one corner and a
/// wall of small text under a title nobody read. Everything here answers one
/// question at a time: what this profile is, what the seller says, what it
/// costs you in traffic and time, what is inside it, and what I can do to it.
class ProfileInstrument extends StatelessWidget {
  const ProfileInstrument({
    super.key,
    required this.title,
    required this.description,
    required this.facts,
    required this.selected,
    required this.onSelect,
    required this.nodes,
    required this.onNodeTap,
    this.selectedNodeTitle,
    this.telegramLabel,
    this.onTelegram,
    this.onRefresh,
    this.refreshing = false,
    this.onShare,
    this.onDelete,
    this.showTelegraph = true,
  });

  final String title;

  /// The seller's own words — the `announce` field, read as prose.
  final String description;

  /// «Ключ · активен · ещё 27 дней», already formatted.
  final List<String> facts;

  final bool selected;
  final VoidCallback onSelect;

  /// The pool, rendered as instrument lines rather than a list.
  final List<NodeLine> nodes;
  final void Function(int index) onNodeTap;
  final String? selectedNodeTitle;

  final String? telegramLabel;
  final VoidCallback? onTelegram;
  final VoidCallback? onRefresh;
  final bool refreshing;
  final VoidCallback? onShare;
  final VoidCallback? onDelete;
  final bool showTelegraph;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final mute = dark ? AppBrand.inkMutedDark : AppBrand.inkMutedLight;
    final l = AppL10n.of(context);

    // The seller writes one block; the lines under it are detail. Splitting on
    // the line break is honest to the document — `announce` is a short text
    // with a headline and a few facts — and it stops the whole notice reading
    // as one paragraph of equal weight.
    final lines = description
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final headline = lines.isEmpty ? '' : lines.first;
    final detail = lines.length < 2 ? const <String>[] : lines.sublist(1);

    return AppSurface(
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name on the left, the whole toolbar on the right: the actions
                // read as the continuation of the name, not as a row of slabs
                // under the card.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        title.toUpperCase(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                          fontSize: 17,
                          height: 1.15,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _Toolbar(
                      selected: selected,
                      busy: refreshing,
                      onSelect: onSelect,
                      onRefresh: onRefresh,
                      onShare: onShare,
                      onDelete: onDelete,
                    ),
                  ],
                ),
                if (facts.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final fact in facts)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.05),
                          ),
                          child: Text(
                            fact,
                            style: TextStyle(
                              fontSize: 11.5,
                              letterSpacing: 0.4,
                              color: mute,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                if (headline.isNotEmpty || detail.isNotEmpty) ...[
                  const SizedBox(height: 13),
                  // Two blocks: what the seller says, and what the seller
                  // wants me to know. Both are read, not scanned.
                  LayoutBuilder(
                    builder: (context, box) {
                      // Bounded only: a Row with Expanded under an unbounded
                      // width throws, and this card is also measured inside
                      // unbounded probes.
                      final wide = box.hasBoundedWidth &&
                          box.maxWidth > 420 &&
                          detail.isNotEmpty;
                      final headlineBlock = headline.isEmpty
                          ? null
                          : _Block(
                              accent: true,
                              child: Text(
                                headline,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontSize: 13.5,
                                  height: 1.45,
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.9),
                                ),
                              ),
                            );
                      final detailBlock = detail.isEmpty
                          ? null
                          : _Block(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (var i = 0; i < detail.length; i++) ...[
                                    if (i > 0) const SizedBox(height: 4),
                                    Text(
                                      detail[i],
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                        fontSize: 12.5,
                                        height: 1.4,
                                        color: mute,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            );
                      if (!wide) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (headlineBlock != null) headlineBlock,
                            if (detailBlock != null) ...[
                              const SizedBox(height: 8),
                              detailBlock,
                            ],
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 5,
                            child: headlineBlock ?? const SizedBox.shrink(),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 4,
                            child: detailBlock ?? const SizedBox.shrink(),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
          if (nodes.isNotEmpty) ...[
            Divider(height: 1, color: theme.colorScheme.outline),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 14, 8),
              child: Row(
                children: [
                  Text(
                    l.locationsNodes.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 2.2,
                      fontWeight: FontWeight.w700,
                      color: mute,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${nodes.length}',
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w700,
                      color: AppBrand.mascotGoldLit,
                    ),
                  ),
                  const Spacer(),
                  // The seller lives with the servers: this is where a person
                  // goes when the list does not have what they need.
                  if (onTelegram != null)
                    ToolAction(
                      icon: AppIcons.paperPlane,
                      label: telegramLabel ?? l.freeTelegram,
                      onTap: onTelegram,
                      tone: AppActionTone.link,
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                children: [
                  for (var i = 0; i < nodes.length; i++) ...[
                    if (i > 0) const SizedBox(height: 7),
                    nodes[i],
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The actions, as a compact row of squares plus the one key that matters.
/// They sit on the name's line: a profile and what you can do with it read as
/// one object.
class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.selected,
    required this.busy,
    required this.onSelect,
    this.onRefresh,
    this.onShare,
    this.onDelete,
  });

  final bool selected;
  final bool busy;
  final VoidCallback onSelect;
  final VoidCallback? onRefresh;
  final VoidCallback? onShare;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onRefresh != null)
          ToolAction(
            icon: AppIcons.refresh,
            label: l.freeRefresh,
            onTap: onRefresh,
            busy: busy,
            compact: true,
          ),
        if (onRefresh != null && onShare != null) const SizedBox(width: 6),
        if (onShare != null)
          ToolAction(
            icon: AppIcons.share,
            label: l.locationsShareKey,
            onTap: onShare,
            compact: true,
          ),
        if (onShare != null && onDelete != null) const SizedBox(width: 6),
        if (onDelete != null)
          ToolAction(
            icon: AppIcons.trash,
            label: l.freeDelete,
            onTap: onDelete,
            tone: AppActionTone.danger,
            compact: true,
          ),
        const SizedBox(width: 8),
        ToolAction(
          icon: selected ? AppIcons.check : AppIcons.play,
          label: selected ? l.locationsInUse : l.locationsUseIt,
          onTap: onSelect,
          tone: AppActionTone.primary,
        ),
      ],
    );
  }
}

/// One quiet block of text inside the card.
class _Block extends StatelessWidget {
  const _Block({required this.child, this.accent = false});

  final Widget child;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(
            color: accent
                ? AppBrand.mascotGold.withValues(alpha: 0.55)
                : theme.colorScheme.outline,
            width: accent ? 2.5 : 1,
          ),
        ),
      ),
      child: child,
    );
  }
}

/// Facts for the instrument header, built from what the document really says.
List<String> profileFacts({
  required String? trafficMeta,
  required String? lastUpdated,
  required bool russian,
  required String keyHandle,
}) {
  final out = <String>[];
  final handle = keyHandle.trim();
  if (handle.isNotEmpty) out.add(handle);
  final traffic = parseSubscriptionTraffic(trafficMeta);
  final label = formatSubscriptionTraffic(traffic, russian: russian);
  if (label.trim().isNotEmpty) out.add(label.trim());
  final updated = lastUpdated?.trim();
  if (updated != null && updated.isNotEmpty) out.add(updated);
  return out;
}