import 'package:flutter/material.dart';

import '../../../core/ios_store_gates.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/app_action_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_surface.dart';
import '../../../l10n/app_localizations.dart';
import '../data/subscription_label.dart';
import 'server_glyph.dart';

/// Paste, and on the phone a matching QR. Windows has no camera and no QR.
///
/// [onRefresh] reloads saved subscription documents. On the phone it is a
/// small ring control beside QR; on Windows it is a full key beside Paste.
/// Every action wears a colour sampled off the mascot: paste takes the house
/// gold, QR the ember under it, and the reload only a ring of the same light —
/// the yard is already busy enough.
class FreeClientActionBar extends StatelessWidget {
  const FreeClientActionBar({
    super.key,
    required this.onPaste,
    required this.onScan,
    this.onRefresh,
    this.draft = false,
  });

  final VoidCallback onPaste;
  final VoidCallback onScan;
  final VoidCallback? onRefresh;

  /// True on the import screen's first step.
  ///
  /// There the key does not add a server — the server is added by the key at
  /// the bottom of the screen — it puts the clipboard into the field above.
  /// Saying «Добавить сервер» twice on one screen made a person wonder which
  /// one actually adds it. Nothing here reloads either: there is nothing saved
  /// yet to reload.
  final bool draft;

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    const barHeight = 54.0;
    const gap = SizedBox(width: 10);
    // Add server is the primary: it is the only thing a person has to do to get
    // this screen to work, so it wears the house's own gold. Reload wears the
    // cool counterpart — the same harmony read from the other side of the
    // wheel, and the colour says "this talks to the network" without a word.
    final add = AppActionButton(
      onPressed: onPaste,
      icon: draft ? AppIcons.clipboard : AppIcons.plus,
      label: draft ? l.freePaste : l.freeAddServer,
      color: AppBrand.mascotGold,
      height: barHeight,
    );
    final refresh = draft ? null : onRefresh;
    if (windowsDesktop) {
      // Windows has no camera, so the reload takes the free slot as a full key.
      if (refresh == null) {
        return SizedBox(
            height: barHeight, width: double.infinity, child: add);
      }
      return SizedBox(
        height: barHeight,
        child: Row(
          children: [
            Expanded(child: add),
            gap,
            Expanded(
              child: AppActionButton(
                onPressed: refresh,
                icon: AppIcons.refresh,
                label: l.freeRefresh,
                color: AppBrand.actionSky,
                height: barHeight,
              ),
            ),
          ],
        ),
      );
    }
    return SizedBox(
      height: barHeight,
      child: Row(
        children: [
          Expanded(child: add),
          gap,
          AppRingButton(
            icon: AppIcons.refresh,
            color: AppBrand.actionSky,
            onPressed: refresh,
            tooltip: l.freeRefresh,
            size: barHeight,
          ),
          gap,
          AppRingButton(
            icon: AppIcons.qrCode,
            color: AppBrand.mascotGoldDeep,
            onPressed: onScan,
            tooltip: l.freeQr,
            size: barHeight,
          ),
        ],
      ),
    );
  }
}

class FreeClientEmptyState extends StatelessWidget {
  const FreeClientEmptyState({super.key, this.compact = false});

  final bool compact;

  /// The DOM mark, the same plate the launcher icon, the bottom nav and the
  /// download card carry — not a generic folder glyph. It is self-contained, so
  /// it needs no tint per theme, and it must not be ColorFiltered: that crushes
  /// the DOM cutout.
  static const _markAsset = 'assets/icon/logo_mark_nav.png';

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          _markAsset,
          width: compact ? 40 : 56,
          height: compact ? 40 : 56,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          // The title and body below already name what is missing.
          excludeFromSemantics: true,
        ),
        SizedBox(height: compact ? 8 : 12),
        Text(
          l.freeEmptyTitle,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          windowsDesktop ? l.freeAddHint : l.freeEmptyBody,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// The head of the home screen: a quiet terminal.
///
/// Not the green-on-black hightech cliché — this is a lamp on a night, read at
/// a glance. Monospace and letterspaced so the numbers line up like an
/// instrument, warm gold instead of neon, and nothing brighter than the house
/// itself. The three fields are spread across the width with the state in the
/// middle: where it is going, what it is doing, how long it has been up.
class ConnectionTerminal extends StatelessWidget {
  const ConnectionTerminal({
    super.key,
    required this.label,
    required this.status,
    required this.serverName,
    required this.accent,
    this.tile = PoolTile.flag,
    this.serverFlag,
    this.uptime,
    this.trafficLabel,
    this.trafficUsed = 0,
    this.trafficCap = 0,
    this.trafficColor,
  });

  /// What this screen is.
  final String label;
  final String status;

  /// The server, with its flag, inside the terminal next to the state.
  final String serverName;
  final String? serverFlag;

  /// What the mark beside the name is: a country, YouTube, or a gamepad.
  final PoolTile tile;

  final Color accent;
  final String? uptime;
  final String? trafficLabel;

  /// Fraction of the cap already spent, 0…1. Zero cap means unlimited.
  final double trafficUsed;
  final double trafficCap;

  final Color? trafficColor;

  /// The terminal's own type.
///
/// A real monospace, bundled: JetBrains Mono has native Cyrillic, which the
/// platform's `monospace` does not promise and which showed up as tofu on a
/// machine with no mono installed. Everything else is Onest.
TextStyle _mono(
    BuildContext context, {
    required double size,
    required Color color,
    double weight = 600,
    double spacing = 1.1,
  }) {
    return TextStyle(
      fontFamily: 'JetBrainsMono',
      fontFamilyFallback: const ['Onest', 'Inter'],
      fontSize: size,
      fontWeight: weight >= 700 ? FontWeight.w700 : FontWeight.w400,
      color: color,
      letterSpacing: spacing,
      height: 1.2,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final mute = dark ? AppBrand.inkMutedDark : AppBrand.inkMutedLight;
    final ink = theme.colorScheme.onSurface;
    final capped = trafficCap > 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '▌',
              style: _mono(
                context,
                size: 13,
                // The block is a lamp, the word is a name.
                //
                // It has been both wrong ways round: first it wore the state
                // colour and made the word «ПОДКЛЮЧЕНИЕ» look like a reading,
                // then it was pinned to the house gold and stayed gold through
                // an error — a lit lamp on a screen whose own text said the
                // service was down. Now it carries the state and the word keeps
                // the muted ink of a label, so the colour is always the truth
                // and the name is never a second opinion.
                color: accent,
                weight: 700,
                spacing: 0,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _mono(
                  context,
                  size: 11.5,
                  color: mute,
                  weight: 700,
                  spacing: 2.6,
                ),
              ),
            ),
            // Uptime on the counter, where a terminal puts a reading that
            // belongs to the screen rather than to the state: the label at one
            // end of the line and the clock at the other, the same measure the
            // traffic rail keeps below. Turned on its side beside the GB it was
            // a second measurement in a different alphabet — clever, and the
            // first thing a person had to decode.
            if (windowsDesktop && uptime != null) ...[
              const Spacer(),
              _uptimeField(context, ink, mute, uptime),
            ],
          ],
        ),
        const SizedBox(height: 14),
        // Where you are, in the middle and large.
        //
        // The middle used to be the state word — «НЕ ПОДКЛЮЧЕНО» — which is
        // the one fact the house behind it already says with its whole body:
        // dark house, no light, not connected. The thing the head was not
        // saying is *where*, and a country is a picture, so it gets the size
        // and the centre.
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The same mark the profile list draws for this node. It was a
              // globe here and a red YouTube tile there, for the same line:
              // one node, one mark, wherever it appears.
              if (tile == PoolTile.flag) ...[
                FlagMark(flag: serverFlag ?? '', width: 38),
                const SizedBox(width: 12),
              ] else ...[
                ServerGlyph(
                  label: PoolServerLabel(
                    title: serverName,
                    subtitle: '',
                    tile: tile,
                    flag: '',
                  ),
                  size: 38,
                ),
                const SizedBox(width: 12),
              ],
              Flexible(
                child: Text(
                  serverName.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _mono(
                    context,
                    size: 21,
                    color: ink,
                    weight: 700,
                    spacing: 1.6,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // The state under it, small: the lamp is the signal, the word is the
        // caption. Centred, because everything above it is.
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Lamp(color: accent, size: 8),
              const SizedBox(width: 9),
              Flexible(
                child: Text(
                  status.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _mono(
                    context,
                    size: 11,
                    color: accent,
                    weight: 700,
                    spacing: 2.2,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // The rail the traffic runs on, with the spent GB at its end.
        _TrafficRail(
          label: trafficLabel ?? '--',
          value: capped ? trafficUsed.clamp(0.0, 1.0) : 0.0,
          capped: capped,
          color: trafficColor ?? accent,
          mono: _mono,
        ),
      ],
    );
  }

  /// How long the tunnel has been up, as a caption in the head's top line.
  ///
  /// The label sits at the left of that line and the clock at the right, which
  /// is the same measure the traffic rail keeps: two ends of one rule. It was
  /// turned on its side for a while, standing perpendicular to the spent GB —
  /// two measurements at right angles, which is clever and is also the first
  /// thing a person has to decode on a screen that is meant to be read at a
  /// glance.
  Widget _uptimeField(
    BuildContext context,
    Color ink,
    Color mute,
    String? uptime,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'UPTIME',
          style: _mono(
            context,
            size: 9,
            color: mute.withValues(alpha: 0.7),
            spacing: 1.4,
          ),
        ),
        const SizedBox(width: 7),
        Text(
          uptime ?? '--:--:--',
          style: _mono(
            context,
            size: 12.5,
            color: ink.withValues(alpha: 0.78),
          ),
        ),
      ],
    );
  }
}

/// A segmented rail of traffic. Blocks, not a smooth bar: this is the one
/// place on the screen where a number moves, and it should look like it is
/// being counted rather than like a progress animation.
class _TrafficRail extends StatelessWidget {
  const _TrafficRail({
    required this.label,
    required this.value,
    required this.capped,
    required this.color,
    required this.mono,
  });

  final String label;
  final double value;
  final bool capped;
  final Color color;
  final TextStyle Function(BuildContext, {required double size, required Color color, double weight, double spacing})
  mono;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final mute = dark ? AppBrand.inkMutedDark : AppBrand.inkMutedLight;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'ТРАФИК',
              style: mono(
                context,
                size: 9.5,
                color: mute.withValues(alpha: 0.75),
                spacing: 1.8,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 10,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: value),
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeOutCubic,
                  builder: (context, v, _) => CustomPaint(
                    painter: _SegmentBarPainter(
                      value: v,
                      color: color,
                      night: dark,
                    ),
                    isComplex: true,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: mono(
                context,
                size: 11.5,
                color: color,
                weight: 700,
                spacing: 0.6,
              ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ],
        ),
        if (!capped) ...[
          const SizedBox(height: 7),
          Text(
            'БЕЗ ЛИМИТА',
            style: mono(
              context,
              size: 9.5,
              color: mute.withValues(alpha: 0.55),
              spacing: 1.6,
            ),
          ),
        ],
      ],
    );
  }
}

class _SegmentBarPainter extends CustomPainter {
  _SegmentBarPainter({
    required this.value,
    required this.color,
    required this.night,
  });

  final double value;
  final Color color;

  /// The two themes need two different rails, not one rail at two opacities.
  /// On the night the empty cells are the same colour, nearly out: a dark
  /// groove with light in part of it. On paper that trick disappears — 12% of
  /// gold on cream is nothing — so the empty cells become ink instead, a real
  /// groove cut into the sheet, and the filled ones go almost solid because
  /// there is no dark background to make them glow.
  final bool night;

  static const int _cells = 26;
  static const double _gap = 2.4;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = (size.width - _gap * (_cells - 1)) / _cells;
    final filled = (value.clamp(0.0, 1.0) * _cells).roundToDouble();
    for (var i = 0; i < _cells; i++) {
      final x = i * (cell + _gap);
      // The cell under the head glows a little brighter: the leading edge is
      // where the eye goes.
      final isHead = (i + 1 - filled).abs() < 0.5 && filled > 0;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, 1, cell, size.height - 2),
          const Radius.circular(1.2),
        ),
        Paint()
          ..color = i < filled
              ? (isHead
                    ? color
                    : color.withValues(alpha: night ? 0.55 : 0.88))
              : (night
                    ? color.withValues(alpha: 0.12)
                    : AppBrand.inkLight.withValues(alpha: 0.16)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SegmentBarPainter old) =>
      old.value != value || old.color != color || old.night != night;
}

/// The status light. A ring around a filled core, lit by the state colour.
class _Lamp extends StatelessWidget {
  const _Lamp({required this.color, this.size = 12});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.45),
            blurRadius: 12,
            spreadRadius: -2,
          ),
        ],
        border: Border.all(color: color.withValues(alpha: 0.55), width: 1),
      ),
    );
  }
}

/// Instrument panel kept for screens that still want the ruled plate.
class ConnectionStatusPanel extends StatelessWidget {
  const ConnectionStatusPanel({
    super.key,
    required this.status,
    required this.profile,
    required this.traffic,
    required this.accent,
    this.uptime,
    this.trafficColor,
  });

  final String status;
  final String profile;
  final String traffic;
  final Color accent;

  /// How long this connection has been up. Absent when there is no session.
  final String? uptime;
  final Color? trafficColor;

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final mute = dark ? AppBrand.inkMutedDark : AppBrand.inkMutedLight;

    // The panel stopped being a ruled notebook table and became an instrument:
    // the label is a caption, the value is the only thing set at reading size,
    // and the numbers use tabular figures so a ticking clock does not shuffle
    // the row while it runs.
    final rows = <({String label, String value, bool numeric, Color? color})>[
      (label: l.freeStatus, value: status, numeric: false, color: accent),
      (label: l.freeProfile, value: profile, numeric: false, color: null),
      (
        label: l.freeTrafficLeft,
        value: traffic,
        numeric: true,
        color: trafficColor,
      ),
      if (uptime != null)
        (label: l.freeUptime, value: uptime!, numeric: true, color: mute),
    ];

    return AppSurface(
      padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The status light sits on the edge of the plate: the colour reads
            // before the words do, and every row stays on one baseline.
            Container(
              width: 3,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(2),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.35),
                    blurRadius: 10,
                    spreadRadius: -2,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                children: [
                  for (final (index, row) in rows.indexed) ...[
                    if (index > 0) const _PanelRule(),
                    _InstrumentRow(
                      label: row.label,
                      value: row.value,
                      numeric: row.numeric,
                      color: row.color,
                      mute: mute,
                      emphasize: index == 0,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hairline between instrument rows — a printed rule on the plate, not the
/// orange margin rule the notebook sheet uses.
class _PanelRule extends StatelessWidget {
  const _PanelRule();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      // The rule is a printed line, not a band: it borrows no vertical budget
      // of its own, so three rows stay as short as they were before the panel
      // became an instrument. Anything else overflows on a 600pt window.
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Container(
        height: 1,
        color: dark
            ? AppBrand.lightSource.withValues(alpha: 0.07)
            : AppBrand.shadeSource.withValues(alpha: 0.07),
      ),
    );
  }
}

class _InstrumentRow extends StatelessWidget {
  const _InstrumentRow({
    required this.label,
    required this.value,
    required this.numeric,
    required this.mute,
    required this.emphasize,
    this.color,
  });

  final String label;
  final String value;
  final bool numeric;
  final Color mute;
  final bool emphasize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        // Caption and value share the row by weight, not 50/50: a status like
        // «Не подключено» needs more than half the line to set at 16.5pt.
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Flexible(
            flex: 2,
            child: Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: mute,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.end,
              // The status can be a whole sentence («Служба недоступна»):
              // one line clipped it. The other rows are short values.
              maxLines: emphasize ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                color: color ?? theme.colorScheme.onSurface,
                fontSize: emphasize ? 16.5 : 15.5,
                fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
                letterSpacing: -0.2,
                fontFeatures:
                    numeric ? const [FontFeature.tabularFigures()] : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ImportedProfileCard extends StatelessWidget {
  const ImportedProfileCard({
    super.key,
    required this.name,
    required this.scheme,
    required this.endpoint,
    required this.selected,
    this.connected = false,
    this.dialable = true,
    this.onTap,
    this.onDelete,
  });

  final String name;
  final String scheme;
  final String endpoint;
  final bool selected;
  final bool connected;
  final bool dialable;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppL10n.of(context);
    return Material(
      color: selected
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppBrand.radiusCard),
        side: BorderSide(
          color:
              selected ? theme.colorScheme.primary : theme.colorScheme.outline,
          width: selected ? 1.6 : 1,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        title: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Text(
          dialable ? endpoint : l.freeSchemeParked,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        leading: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.colorScheme.outline),
          ),
          child: Text(
            scheme.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (connected)
              const Icon(AppIcons.checkCircleFill,
                  color: AppBrand.success, size: 18),
            if (onDelete != null)
              SheetTintTrashButton(
                tooltip: l.freeDelete,
                onPressed: onDelete!,
              ),
          ],
        ),
      ),
    );
  }
}

/// Asks before a server or a whole list is removed.
Future<bool> confirmImportedDelete(
  BuildContext context, {
  required bool catalog,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final l = AppL10n.of(dialogContext);
      return AlertDialog(
        title: Text(
          catalog ? l.freeDeleteCatalogTitle : l.freeDeleteServerTitle,
        ),
        content: Text(
          catalog ? l.freeDeleteCatalogBody : l.freeDeleteServerBody,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l.freeDelete),
          ),
        ],
      );
    },
  );
  return ok == true;
}

/// Trash sits on a patch the color of the notebook sheet.
class SheetTintTrashButton extends StatelessWidget {
  const SheetTintTrashButton({
    super.key,
    required this.onPressed,
    required this.tooltip,
  });

  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: dark ? AppBrand.paperDark : AppBrand.paperLight,
      borderRadius: BorderRadius.circular(12),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: const AppIcon(AppIcons.trash, size: 20),
      ),
    );
  }
}
