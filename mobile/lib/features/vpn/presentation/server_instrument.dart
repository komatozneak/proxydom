import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/app_action_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_surface.dart';
import '../../../core/widgets/terminal_type.dart';
import '../../../l10n/app_localizations.dart';
import '../data/profile_manifest.dart';
import '../data/subscription_traffic.dart';
import 'server_instrument_parts.dart';

const kProfileTrafficBarKey = ValueKey<String>('profile-traffic-bar');

String _number(double value, {required bool russian}) {
  final shown = value.toStringAsFixed(1);
  return russian ? shown.replaceAll('.', ',') : shown;
}

bool _trafficIsStale(DateTime? at, int? intervalHours) {
  if (at == null) return false;
  final limitHours =
      ((intervalHours == null ? 48 : intervalHours * 2)).clamp(12, 168).toInt();
  final age = DateTime.now().toUtc().difference(at);
  return !age.isNegative && age.inHours > limitHours;
}

/// A bought profile, drawn as an instrument.
///
/// One plate, two sections: the hoster's profile band, then its node pool.
/// Every visible string is document data — title, announce, support URL,
/// traffic and update stamp. The widget adds no owner-specific copy, so a
/// hoster can supply their own profile in the subscription document. The gold
/// left rail and traffic reading give the profile its weight; the node header
/// follows on the same surface, not on a second card.
class ProfileInstrument extends StatelessWidget {
  const ProfileInstrument({
    super.key,
    required this.title,
    required this.description,
    required this.facts,
    this.parsedTraffic,
    this.manifestTraffic,
    this.planName,
    this.trafficUpdatedAt,
    this.updateIntervalHours,
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

  /// The document's cap, if it had one. Drives the watermark and the bar.
  final SubscriptionTraffic? parsedTraffic;

  /// New-style quota from `proxydom-profile`. It wins over [parsedTraffic].
  final ProfileTraffic? manifestTraffic;

  final String? planName;
  final DateTime? trafficUpdatedAt;
  final int? updateIntervalHours;

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

    // One neutral plate, not a brown card inside a dark one: the profile band
    // is lifted a few percent from the surface and the gold spine carries the
    // identity. Hoster content, not synthetic labels, gives it its shape.
    final tint = dark
        ? Color.lerp(
            theme.colorScheme.surface,
            AppBrand.lightSource,
            selected ? 0.045 : 0.022,
          )!
        : Color.lerp(
            theme.colorScheme.surface,
            AppBrand.mascotGold,
            selected ? 0.04 : 0.016,
          )!;

    final russian = Localizations.localeOf(context).languageCode == 'ru';
    final legacy = parsedTraffic;
    final manifest = manifestTraffic;
    final unlimited = manifest?.unlimited == true ||
        (manifest == null && legacy?.unlimited == true);
    final usedBytes = manifest?.usedBytes ??
        (legacy == null ? 0 : legacy.upload + legacy.download);
    final totalBytes = manifest?.total ??
        (legacy != null && !legacy.unlimited ? legacy.total : null);
    final capped = !unlimited && totalBytes != null && totalBytes > 0;
    final exhausted = capped && usedBytes >= totalBytes;
    final usedOnly = !unlimited && !capped && usedBytes > 0;
    final ratio = capped ? (usedBytes / totalBytes).clamp(0.0, 1.0) : null;
    final percent = ratio == null ? null : ratio * 100;
    final percentLabel = percent == null
        ? null
        : percent < 10
            ? _number(percent, russian: russian)
            : percent.round().toString();
    final remainingBytes =
        capped ? (totalBytes - usedBytes).clamp(0, totalBytes) : null;
    final watermark = unlimited
        ? '∞'
        : capped
            ? formatTrafficAmount(remainingBytes!, russian: russian)
            : usedOnly
                ? formatTrafficAmount(usedBytes, russian: russian)
                : '—';
    final usedLabel =
        ratio == null ? null : formatTrafficAmount(usedBytes, russian: russian);
    final totalLabel = ratio == null
        ? null
        : formatTrafficAmount(totalBytes!, russian: russian);
    final barColor = exhausted
        ? (dark ? AppBrand.inkDangerDark : AppBrand.inkDangerLight)
        : ratio != null && ratio >= 0.8
            ? AppBrand.flame
            : gold;
    final stale = _trafficIsStale(trafficUpdatedAt, updateIntervalHours);
    final meta = updated == null
        ? (stale ? l.profileTrafficStale : null)
        : stale
            ? '${updated!} · ${l.profileTrafficStale}'
            : updated;

    final profile = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: tint,
        border: Border(
          left: BorderSide(
            color: gold.withValues(alpha: selected ? 0.9 : 0.5),
            width: 3,
          ),
        ),
      ),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            right: 10,
            top: 2,
            child: ExcludeSemantics(
              child: IgnorePointer(
                child: Text(
                  watermark,
                  maxLines: 1,
                  textAlign: TextAlign.right,
                  style: terminalText(
                    context,
                    size: 58,
                    color: gold.withValues(alpha: dark ? 0.075 : 0.055),
                    weight: 700,
                    spacing: 0.2,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 12),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontSize: 27,
                      fontWeight: FontWeight.w800,
                      height: 1.08,
                      letterSpacing: -0.4,
                    ),
                  ),
                  if (planName != null && planName!.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      planName!.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: terminalText(
                        context,
                        size: 10,
                        color: gold,
                        weight: 700,
                        spacing: 1.4,
                      ),
                    ),
                  ],
                  if (captions.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _FactsLine(facts: captions, mute: mute),
                  ],
                  if (ratio != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${l.profileTrafficUsed} $usedLabel / $totalLabel',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: terminalText(
                              context,
                              size: 10.5,
                              color: mute,
                              weight: 600,
                              spacing: 0.2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$percentLabel%',
                          style: terminalText(
                            context,
                            size: 10.5,
                            color: barColor,
                            weight: 700,
                            spacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      key: kProfileTrafficBarKey,
                      borderRadius: BorderRadius.circular(99),
                      child: SizedBox(
                        height: 4,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ColoredBox(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.08),
                            ),
                            TweenAnimationBuilder<double>(
                              tween: Tween<double>(begin: 0, end: ratio),
                              duration: const Duration(milliseconds: 450),
                              curve: Curves.easeOutCubic,
                              builder: (context, value, child) {
                                return FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: value,
                                  child: ColoredBox(color: barColor),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (exhausted) ...[
                      const SizedBox(height: 5),
                      Text(
                        l.homeTrafficExhausted,
                        style: terminalText(
                          context,
                          size: 10.5,
                          color: barColor,
                          weight: 700,
                          spacing: 0.2,
                        ),
                      ),
                    ],
                  ] else if (unlimited) ...[
                    const SizedBox(height: 8),
                    Text(
                      l.homeTrafficUnlimited,
                      style: terminalText(
                        context,
                        size: 11,
                        color: gold,
                        weight: 700,
                        spacing: 1.2,
                      ),
                    ),
                    if (usedBytes > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${l.profileTrafficUsed} ${formatTrafficAmount(usedBytes, russian: russian)}',
                        style: terminalText(
                          context,
                          size: 10.5,
                          color: mute,
                          weight: 600,
                          spacing: 0.2,
                        ),
                      ),
                    ],
                  ] else if (usedOnly) ...[
                    const SizedBox(height: 7),
                    Text(
                      '${l.profileTrafficUsed} ${formatTrafficAmount(usedBytes, russian: russian)}',
                      style: terminalText(
                        context,
                        size: 11,
                        color: gold,
                        weight: 700,
                        spacing: 0.2,
                      ),
                    ),
                  ] else if (traffic != null) ...[
                    const SizedBox(height: 7),
                    Text(
                      traffic,
                      style: terminalText(
                        context,
                        size: 18,
                        color: gold,
                        weight: 700,
                        spacing: 0.2,
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 7),
                    Text(
                      l.profileTrafficNoData,
                      style: terminalText(
                        context,
                        size: 10.5,
                        color: mute,
                        weight: 600,
                        spacing: 0.2,
                      ),
                    ),
                  ],
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 9),
                    Text(
                      description,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 13.5,
                        height: 1.45,
                        fontWeight: FontWeight.w600,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.82),
                      ),
                    ),
                  ],
                  if (onTelegram != null) ...[
                    const SizedBox(height: 7),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ToolAction(
                        icon: AppIcons.paperPlane,
                        label: telegramLabel ?? l.freeTelegram,
                        onTap: onTelegram,
                        tone: AppActionTone.link,
                        dense: true,
                      ),
                    ),
                  ],
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      if (meta != null && meta.trim().isNotEmpty)
                        Expanded(
                          child: Text(
                            meta.trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: stale
                                  ? (dark
                                      ? AppBrand.flame
                                      : AppBrand.mascotGoldDeep)
                                  : mute,
                              fontSize: 11.5,
                            ),
                          ),
                        )
                      else
                        const Spacer(),
                      const SizedBox(width: 8),
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
                ],
              ),
            ),
          ),
        ],
      ),
    );

    return AppSurface(
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          profile,
          const _PlateRule(),
          if (nodes.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
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
                    const SizedBox(width: 8),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: _LiveNode(name: selectedNodeTitle!),
                      ),
                    ),
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
          ],
          if (unsupportedNote != null && unsupportedNote!.trim().isNotEmpty)
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
        Flexible(
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
