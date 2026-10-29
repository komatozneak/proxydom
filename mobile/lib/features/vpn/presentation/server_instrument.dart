import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/app_action_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_surface.dart';
import '../../../core/widgets/terminal_type.dart';
import '../../../l10n/app_localizations.dart';
import '../data/subscription_traffic.dart';
import 'server_instrument_parts.dart';

/// The profile pass and the node pool are separate plates, not one long card.
const kProfilePassKey = ValueKey<String>('profile-pass');
const kProfilePoolKey = ValueKey<String>('profile-pool');

/// A bought profile, drawn as an instrument.
///
/// The profile is a detached ticket pass: a warm paper tint, a gold spine, the
/// remaining traffic as the largest reading on the page, and a punched stub
/// carrying the update stamp. The node pool is a second plate with its own
/// header; the two never dissolve into one long surface. What you can do to the
/// profile sits on the right of its name, in rings rather than squares — quiet
/// controls that do not outrank the thing they act on.
class ProfileInstrument extends StatelessWidget {
  const ProfileInstrument({
    super.key,
    required this.title,
    required this.description,
    required this.facts,
    this.updated,
    required this.selected,
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
    this.unsupportedNote,
  });

  final String title;

  /// The seller's own words — the `announce` field, read as prose.
  final String description;

  /// «Ключ · 14 ГБ», already formatted. One reading may be the traffic figure,
  /// which is the only fact on the card worth a colour. The update stamp is
  /// not one of these: it sits under the rings, not in this line.
  final List<({String text, bool accent})> facts;

  /// «обновлено 04.10», already formatted. Drawn on the pass stub.
  final String? updated;

  final bool selected;

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

  /// Lines the parser kept out of [nodes], with a reason each. Neutral.
  final String? unsupportedNote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final mute = dark ? AppBrand.inkMutedDark : AppBrand.inkMutedLight;
    final l = AppL10n.of(context);
    final gold = goldInk(context);

    String? traffic;
    final captions = <({String text, bool accent})>[];
    for (final fact in facts) {
      if (fact.accent && traffic == null) {
        traffic = fact.text;
      } else {
        captions.add(fact);
      }
    }

    // The profile is a pass, not a card header: tinted paper, a gold spine,
    // a punched dashed rule and a stub with the update stamp. The node pool is
    // a separate plate below it, so the quota and the servers no longer dissolve
    // into one long surface.
    final tint = Color.lerp(
      theme.colorScheme.surface,
      AppBrand.mascotGold,
      selected ? (dark ? 0.10 : 0.07) : (dark ? 0.05 : 0.035),
    )!;

    final pass = AppSurface(
      key: kProfilePassKey,
      clip: true,
      tint: tint,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 3,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: gold.withValues(alpha: selected ? 0.95 : 0.60),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(17, 15, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            l.freeProfile.toUpperCase(),
                            style: terminalText(
                              context,
                              size: 10,
                              color: gold.withValues(alpha: 0.9),
                              weight: 700,
                              spacing: 2.2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge,
                          ),
                          if (captions.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            _FactsLine(facts: captions, mute: mute),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    _Toolbar(
                      busy: refreshing,
                      refreshLabel: l.freeRefresh,
                      onRefresh: onRefresh,
                      shareLabel: l.locationsShareKey,
                      onShare: onShare,
                      deleteLabel: l.freeDelete,
                      onDelete: onDelete,
                    ),
                  ],
                ),
                if (traffic != null) ...[
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          l.freeTrafficLeft.toUpperCase(),
                          style: terminalText(
                            context,
                            size: 9.5,
                            color: mute,
                            weight: 700,
                            spacing: 1.4,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        traffic,
                        style: terminalText(
                          context,
                          size: 30,
                          color: gold,
                          weight: 700,
                          spacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                ],
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, box) {
                      final note = Text(
                        description,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 13.5,
                          height: 1.45,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.88),
                        ),
                      );
                      final link = onTelegram == null
                          ? null
                          : ToolAction(
                              icon: AppIcons.paperPlane,
                              label: telegramLabel ?? l.freeTelegram,
                              onTap: onTelegram,
                              tone: AppActionTone.link,
                              dense: true,
                            );
                      final side = box.hasBoundedWidth &&
                          box.maxWidth >= 460 &&
                          link != null;
                      return _Block(
                        child: side
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(child: note),
                                  const SizedBox(width: 12),
                                  link,
                                ],
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  note,
                                  if (link != null) ...[
                                    const SizedBox(height: 12),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: link,
                                    ),
                                  ],
                                ],
                              ),
                      );
                    },
                  ),
                ],
                const SizedBox(height: 14),
                _Perforation(
                  line: mute.withValues(alpha: 0.32),
                  punch: gold.withValues(alpha: 0.75),
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    if (updated != null && updated!.trim().isNotEmpty)
                      Text(
                        updated!.trim(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: mute,
                          fontSize: 11.5,
                        ),
                      ),
                    const Spacer(),
                    _TicketBars(color: gold.withValues(alpha: 0.55)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );

    final pool = nodes.isEmpty
        ? null
        : AppSurface(
            key: kProfilePoolKey,
            clip: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _PlateRule(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 11, 16, 9),
                  child: Row(
                    children: [
                      Text(
                        l.locationsNodes,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: mute,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${nodes.length}',
                        style: terminalText(
                          context,
                          size: 10,
                          color: gold,
                          weight: 700,
                          spacing: 1,
                        ),
                      ),
                      if (selectedNodeTitle != null) ...[
                        const Spacer(),
                        _LiveNode(name: selectedNodeTitle!),
                      ],
                    ],
                  ),
                ),
                Column(
                  children: [
                    for (var i = 0; i < nodes.length; i++) ...[
                      if (i > 0) const NodeRule(),
                      nodes[i],
                    ],
                  ],
                ),
                if (unsupportedNote != null &&
                    unsupportedNote!.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Text(
                      unsupportedNote!,
                      style: terminalText(
                        context,
                        size: 12,
                        color: mute,
                        weight: 500,
                        spacing: 0.2,
                      ),
                    ),
                  ),
              ],
            ),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        pass,
        if (pool != null) ...[
          const SizedBox(height: 14),
          pool,
        ],
      ],
    );
  }
}

/// «2AQ93K0 · 14 ГБ». The update stamp is not in this line.
///
/// They were three grey pills: three small boxes carrying three small grey
/// words, and louder on the card than the note under them. A line of tracked
/// mono with a dot between the readings says what you have. The traffic figure
/// itself wears the house gold, because it is the one number a person watches
/// run down. When the document was last read sits under the rings.
class _FactsLine extends StatelessWidget {
  const _FactsLine({required this.facts, required this.mute});

  final List<({String text, bool accent})> facts;
  final Color mute;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gold = goldInk(context);
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < facts.length; i++) ...[
          if (i > 0)
            Container(
              width: 3,
              height: 3,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: mute.withValues(alpha: 0.55),
              ),
            ),
          Text(
            facts[i].text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: facts[i].accent ? gold : mute,
              fontSize: 12.5,
            ),
          ),
        ],
      ],
    );
  }
}

/// «АКТИВЕН ● YOUTUBE» on the right end of the pool rule.
///
/// Labelled, not implied: a bare name beside a count reads as one word run
/// together.
class _LiveNode extends StatelessWidget {
  const _LiveNode({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final mute = dark ? AppBrand.inkMutedDark : AppBrand.inkMutedLight;
    final gold = goldInk(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(width: 10),
        Text(
          AppL10n.of(context).locationsActive,
          style: theme.textTheme.labelSmall?.copyWith(
            color: mute,
            fontWeight: FontWeight.w700,
            fontSize: 11.5,
          ),
        ),
        const SizedBox(width: 7),
        Container(
          width: 4,
          height: 4,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppBrand.mascotGold,
          ),
        ),
        const SizedBox(width: 7),
        ConstrainedBox(
          // Room for the name, but never more than the rule has: a long one
          // ellipsises instead of pushing the count off the left end.
          constraints: const BoxConstraints(maxWidth: 140),
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: theme.textTheme.labelSmall?.copyWith(
              color: gold,
              fontWeight: FontWeight.w700,
              fontSize: 11.5,
            ),
          ),
        ),
      ],
    );
  }
}

/// The actions, as rings.
///
/// Three bordered squares in the corner of a card were the loudest thing on it:
/// a red-framed box for the trash and two more beside it, all the same weight as
/// the mark in the name. Rings keep the same three answers and the same target,
/// and leave the name the loudest thing on the plate. Refresh stays the sky of
/// a network call. Copy wears the same gold as «Добавить сервер». The bin is
/// clay, not an alarm: the dialog it opens is where the decision is made.
///
/// There is no connect key. It said «Подключено» in one place and
/// «Подключить» in another, and it asked the card a question the node list
/// already answers: the line you tap is the line you get.
class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.busy,
    required this.refreshLabel,
    required this.shareLabel,
    required this.deleteLabel,
    this.onRefresh,
    this.onShare,
    this.onDelete,
  });

  final bool busy;
  final String refreshLabel;
  final String shareLabel;
  final String deleteLabel;
  final VoidCallback? onRefresh;
  final VoidCallback? onShare;
  final VoidCallback? onDelete;

  static const double _size = 40;
  static const double _iconSize = 18;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = theme.colorScheme.onSurfaceVariant;
    final danger = theme.brightness == Brightness.dark
        ? AppBrand.inkDangerDark
        : AppBrand.inkDangerLight;
    final hasMenu = onShare != null || onDelete != null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onRefresh != null)
          _ring(
            icon: AppIcons.refresh,
            color: ink,
            tooltip: refreshLabel,
            onTap: busy ? null : onRefresh,
            busy: busy,
          ),
        if (onRefresh != null && hasMenu) const SizedBox(width: 2),
        if (hasMenu)
          PopupMenuButton<String>(
            tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
            icon: AppIcon(AppIcons.more, size: 20, color: ink),
            onSelected: (value) {
              if (value == 'share') onShare?.call();
              if (value == 'delete') onDelete?.call();
            },
            itemBuilder: (context) => [
              if (onShare != null)
                PopupMenuItem(
                  value: 'share',
                  child: Row(
                    children: [
                      const AppIcon(AppIcons.share, size: 18),
                      const SizedBox(width: 10),
                      Flexible(child: Text(shareLabel)),
                    ],
                  ),
                ),
              if (onDelete != null)
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      AppIcon(AppIcons.trash, size: 18, color: danger),
                      const SizedBox(width: 10),
                      Flexible(child: Text(deleteLabel)),
                    ],
                  ),
                ),
            ],
          ),
      ],
    );
  }

  /// One control. A spinner stands in for the icon while the reload runs, in
  /// the ring's own colour, so the row never changes width mid-refresh.
  Widget _ring({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback? onTap,
    bool busy = false,
  }) {
    if (!busy) {
      return AppRingButton(
        icon: icon,
        color: color,
        onPressed: onTap,
        tooltip: tooltip,
        size: _size,
        iconSize: _iconSize,
      );
    }
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: _size,
        height: _size,
        child: Center(
          child: SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(strokeWidth: 2, color: color),
          ),
        ),
      ),
    );
  }
}

/// The rule between the head and the pool.
class _PlateRule extends StatelessWidget {
  const _PlateRule();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 1,
      color: dark
          ? AppBrand.lightSource.withValues(alpha: 0.07)
          : AppBrand.shadeSource.withValues(alpha: 0.08),
    );
  }
}

/// One quiet block of text inside the card.
class _Block extends StatelessWidget {
  const _Block({required this.child});

  final Widget child;

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
            color: AppBrand.mascotGold.withValues(alpha: 0.55),
            width: 2.5,
          ),
        ),
      ),
      child: child,
    );
  }
}

/// Facts for the instrument header, built from what the document really says.
///
/// The traffic figure comes back flagged, because it is the one number on the
/// card worth a colour; the key handle is a caption and stays quiet. The
/// update stamp is [profileUpdatedLabel], drawn under the rings.
List<({String text, bool accent})> profileFacts({
  required String? trafficMeta,
  required bool russian,
  required String keyHandle,
}) {
  final out = <({String text, bool accent})>[];
  final handle = keyHandle.trim();
  if (handle.isNotEmpty) out.add((text: handle, accent: false));
  final traffic = parseSubscriptionTraffic(trafficMeta);
  final label = formatSubscriptionTraffic(traffic, russian: russian);
  if (label.trim().isNotEmpty) {
    out.add((text: label.trim(), accent: true));
  }
  return out;
}

/// `обновлено 04.10` — the day the document was last read, for the slot under
/// the rings. Null when the store has no stamp.
String? profileUpdatedLabel({
  required String? lastUpdated,
  required bool russian,
}) {
  return _updatedLabel(lastUpdated, russian: russian);
}

/// `обновлено 04.10` — never the raw stamp.
///
/// The store keeps the moment of the last refresh as an ISO string, and it was
/// printed straight into a chip: `2026-10-04T12:22:09.665032Z`, twenty-seven
/// characters of fraction that pushed the whole chip row onto a second line and
/// told a person nothing they could read. The day and the month is the fact.
String? _updatedLabel(String? raw, {required bool russian}) {
  final stamp = raw?.trim();
  if (stamp == null || stamp.isEmpty) return null;
  final at = DateTime.tryParse(stamp);
  if (at == null) return stamp;
  final local = at.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  return russian ? 'обновлено $day.$month' : 'updated $day.$month';
}

/// A punched ticket rule: two dots and a dashed tear edge.
class _Perforation extends StatelessWidget {
  const _Perforation({required this.line, required this.punch});

  final Color line;
  final Color punch;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _punchDot(punch),
        const SizedBox(width: 8),
        Expanded(
          child: SizedBox(
            height: 1,
            child: CustomPaint(painter: _DashedRulePainter(line)),
          ),
        ),
        const SizedBox(width: 8),
        _punchDot(punch),
      ],
    );
  }

  Widget _punchDot(Color color) => Container(
        width: 5,
        height: 5,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      );
}

class _DashedRulePainter extends CustomPainter {
  const _DashedRulePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    var x = 0.0;
    while (x < size.width) {
      final end = (x + 5).clamp(0.0, size.width);
      canvas.drawLine(Offset(x, 0.5), Offset(end, 0.5), paint);
      x += 9;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRulePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// A tiny barcode-like mark on the ticket stub. Decorative, not a real code.
class _TicketBars extends StatelessWidget {
  const _TicketBars({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    const widths = [1.5, 2.5, 1.0, 3.0, 1.5, 2.0, 1.0];
    const heights = [7.0, 11.0, 6.0, 10.0, 8.0, 5.0, 9.0];
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < widths.length; i++) ...[
          if (i > 0) const SizedBox(width: 2),
          Container(width: widths[i], height: heights[i], color: color),
        ],
      ],
    );
  }
}
