import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/app_action_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_surface.dart';
import '../../../core/widgets/terminal_type.dart';
import '../../../l10n/app_localizations.dart';
import '../data/subscription_traffic.dart';
import 'server_instrument_parts.dart';

/// A bought profile, drawn as an instrument.
///
/// The card was a coloured slab with three square buttons in one corner, a row
/// of grey chips and a wall of small text under a title nobody read, and every
/// node inside it was a further box. It now reads the way the home head reads:
/// one name in the terminal's own voice, the facts as a single line of
/// readings under it, the seller's note as a margin block, and the pool as ruled
/// lines on one plate. What you can do to the profile sits on the right of its
/// name, in rings rather than squares — quiet controls that do not outrank the
/// thing they act on.
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

  /// «Ключ · активен · ещё 27 дней», already formatted. One reading may be the
  /// traffic figure, which is the only fact on the card worth a colour.
  final List<({String text, bool accent})> facts;

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

    return AppSurface(
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 13),
            // The name and its controls share the line; the readings take the
            // whole width under them. Beside three 30px rings the fact line had
            // 170px to live in, so it broke after the second reading and left a
            // separator hanging at the end of the row.
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        title.toUpperCase(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        // The same face, size and tracking as the node name on
                        // the home head: one profile, one voice, whichever
                        // screen it is read on.
                        style: terminalText(
                          context,
                          size: 16,
                          color: theme.colorScheme.onSurface,
                          weight: 700,
                          spacing: 1.6,
                        ),
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
                if (facts.isNotEmpty) ...[
                  const SizedBox(height: 9),
                  _FactsLine(facts: facts, mute: mute),
                ],
              ],
            ),
          ),
          if (description.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 13),
              child: LayoutBuilder(
                builder: (context, box) {
                  final note = Text(
                    description,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 13.5,
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.88),
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
                  // Beside the note while there is room, under it when there
                  // is not. On a phone the row squeezed the seller's text into
                  // a two-word column with the key taking the rest of the line,
                  // which made the note look like a caption for the button.
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
            ),
          ],
          if (nodes.isNotEmpty) ...[
            const _PlateRule(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 11, 16, 9),
              child: Row(
                children: [
                  Text(
                    l.locationsNodes.toUpperCase(),
                    style: terminalText(
                      context,
                      size: 10,
                      color: mute,
                      weight: 700,
                      spacing: 2.2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${nodes.length}',
                    style: terminalText(
                      context,
                      size: 10,
                      color: goldInk(context),
                      weight: 700,
                      spacing: 1,
                    ),
                  ),
                  if (selectedNodeTitle != null) ...[
                    // One flexible child, not two. A Spacer and the name were
                    // both flexible, so they split the slack down the middle
                    // and the pair floated in the centre of the rule instead of
                    // sitting on its right end.
                    const Spacer(),
                    _LiveNode(name: selectedNodeTitle!),
                  ],
                ],
              ),
            ),
            // The lines touch the plate on both sides and are separated by
            // printed rules: the card reads as one object with a pool in it,
            // not as a stack of little cards.
            Column(
              children: [
                for (var i = 0; i < nodes.length; i++) ...[
                  if (i > 0) const NodeRule(),
                  nodes[i],
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// «2AQ93K0 · 14 ГБ · ОБНОВЛЕНО 04.10».
///
/// They were three grey pills: three small boxes carrying three small grey
/// words, and louder on the card than the note under them. A line of tracked
/// mono with a dot between the readings says one thing — this is what you have,
/// and when it was last checked — and it is the same rule the home head runs
/// its traffic along. The traffic figure itself wears the house gold, because
/// it is the one number a person watches run down.
class _FactsLine extends StatelessWidget {
  const _FactsLine({required this.facts, required this.mute});

  final List<({String text, bool accent})> facts;
  final Color mute;

  @override
  Widget build(BuildContext context) {
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
            facts[i].text.toUpperCase(),
            style: terminalText(
              context,
              size: 10.5,
              color: facts[i].accent ? gold : mute,
              spacing: 1.4,
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
          AppL10n.of(context).locationsActive.toUpperCase(),
          style: terminalText(
            context,
            size: 9.5,
            color: mute.withValues(alpha: 0.7),
            weight: 700,
            spacing: 1.6,
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
            name.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: terminalText(
              context,
              size: 10,
              color: gold,
              weight: 700,
              spacing: 1.4,
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
/// and leave the name the loudest thing on the plate. The trash wears no alarm
/// colour here — it destroys nothing yet, and the dialog it opens is where the
/// decision is made.
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

  static const double _size = 30;
  static const double _iconSize = 15;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    // Refresh is the one control that talks to the network, so it keeps the
    // cool counterpart of the house gold that the rest of the app gives it.
    const wire = AppBrand.actionSky;
    final quiet = dark ? AppBrand.inkMutedDark : AppBrand.inkMutedLight;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onRefresh != null) ...[
          _ring(
            icon: AppIcons.refresh,
            color: wire,
            tooltip: refreshLabel,
            onTap: busy ? null : onRefresh,
            busy: busy,
          ),
          if (onShare != null) const SizedBox(width: 8),
        ],
        if (onShare != null) ...[
          _ring(
            icon: AppIcons.share,
            color: quiet,
            tooltip: shareLabel,
            onTap: onShare,
          ),
          if (onDelete != null) const SizedBox(width: 8),
        ],
        if (onDelete != null)
          _ring(
            icon: AppIcons.trash,
            color: quiet,
            tooltip: deleteLabel,
            onTap: onDelete,
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
/// card worth a colour; the key handle and the update stamp are captions and
/// stay quiet.
List<({String text, bool accent})> profileFacts({
  required String? trafficMeta,
  required String? lastUpdated,
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
  final updated = _updatedLabel(lastUpdated, russian: russian);
  if (updated != null) out.add((text: updated, accent: false));
  return out;
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
