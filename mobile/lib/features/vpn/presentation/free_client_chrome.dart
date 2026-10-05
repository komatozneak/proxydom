import 'package:flutter/material.dart';

import '../../../core/diagnostics/product_log.dart';
import '../../../core/diagnostics/ui_log.dart';
import '../../../core/ios_store_gates.dart';
import '../../../core/theme.dart';
import '../../../core/toasts/proxy_dom_toast.dart';
import '../../../core/widgets/app_action_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_surface.dart';
import '../../../core/widgets/interaction.dart';

import '../../../core/widgets/terminal_type.dart';
import '../../../l10n/app_localizations.dart';
import '../data/hy2_import_store.dart';
import '../data/subscription_label.dart';
import 'server_glyph.dart';

/// How one pass over the saved documents went.
///
/// [documents] is how many saved documents had a URL behind them, [failed] how
/// many of those refused, [links] how many servers are on the tab afterwards.
typedef DocumentReload = ({int links, int documents, int failed});

/// Rereads every saved subscription document and counts what came back.
///
/// This is the one answer to « reread my links ». The home key and the servers
/// key ask the same question and used to have two answers: one that reloaded
/// and said nothing about the selection, one that also handled a selection the
/// reload had dropped. A tunnel left up on a key that is no longer in any list
/// is worse than a stale list, so the handling lives with the reloading.
///
/// [onSelectionLeft] is called when the chosen server is no longer in any
/// document after the pass — the caller owns the tunnel and disconnects there.
Future<DocumentReload> reloadSavedDocuments({
  Future<void> Function()? onSelectionLeft,
}) async {
  final catalogs = await Hy2ImportStore.instance.catalogs();
  final remote = [
    for (final catalog in catalogs)
      if (catalog.url != null && catalog.url!.isNotEmpty) catalog,
  ];
  var failed = 0;
  var selectionLeft = false;
  for (final catalog in remote) {
    try {
      final outcome = await Hy2ImportStore.instance.refreshCatalog(catalog.id);
      if (outcome.selectionLeftThisList) selectionLeft = true;
    } on Exception {
      failed++;
    }
  }
  final links = await Hy2ImportStore.instance.load();
  if (selectionLeft && onSelectionLeft != null) await onSelectionLeft();
  return (
    links: links.length,
    documents: remote.length,
    failed: failed,
  );
}

/// Reloads every saved subscription document and says how it went.
///
/// [scope] is the tab the key was pressed on, so the log says which one it was:
/// the same press answers under the name of the screen it happened on, never
/// under the name of another tab.
Future<void> refreshRemoteDocuments(
  BuildContext context, {
  required String scope,
  Future<void> Function()? onSelectionLeft,
  double bottomInset = 0,
}) async {
  UiLog.action(scope, 'refresh', level: ProductLogLevel.info);
  final l = AppL10n.of(context);
  try {
    final result = await reloadSavedDocuments(
      onSelectionLeft: onSelectionLeft,
    );
    if (!context.mounted) return;
    // Every document failing is a different story from none of them being
    // there: the first is a word worth saying, the second is nothing to report.
    if (result.documents > 0 && result.failed == result.documents) {
      UiLog.action(
        scope,
        'refresh',
        level: ProductLogLevel.warn,
        result: 'fail',
      );
      showProxyDomToast(
        l.freeRefreshFail,
        tone: ToastTone.failure,
        bottomInset: bottomInset,
      );
      return;
    }
    UiLog.action(
      scope,
      'refresh',
      level: ProductLogLevel.info,
      result: 'ok',
      extra: {'links': result.links, 'failed': result.failed},
    );
    showProxyDomToast(
      l.freeRefreshDone(result.links),
      tone: ToastTone.success,
      bottomInset: bottomInset,
    );
  } catch (_) {
    if (!context.mounted) return;
    UiLog.action(
      scope,
      'refresh',
      level: ProductLogLevel.warn,
      result: 'fail',
    );
    showProxyDomToast(
      l.freeRefreshFail,
      tone: ToastTone.failure,
      bottomInset: bottomInset,
    );
  }
}

/// How tall the key bar is, and how much of the page it keeps for itself.
///
/// The bar is pinned to the bottom edge of the page it belongs to, so anything
/// that answers from that page has to stand above it — [kActionBarBottomInset]
/// is that standing room: the keys plus the page's own padding above and below.
const double kActionBarHeight = 54;
const double kActionBarBottomInset = kActionBarHeight + 22;

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
    const barHeight = kActionBarHeight;
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
        return SizedBox(height: barHeight, width: double.infinity, child: add);
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
/// itself. The node is centred and large. The state sits at the left, on the
/// traffic label, and the clock — when there is one — stays at the right.
class ConnectionTerminal extends StatelessWidget {
  const ConnectionTerminal({
    super.key,
    required this.status,
    required this.serverName,
    required this.accent,
    this.tile = PoolTile.flag,
    this.serverFlag,
    this.serverSubtitle,
    this.uptime,
    this.trafficLabel,
    this.trafficUsed = 0,
    this.trafficCap = 0,
    this.trafficColor,
  });

  final String status;

  /// The server, with its flag, inside the terminal next to the state.
  final String serverName;
  final String? serverFlag;

  /// The node's own note («низкий пинг»), under the name. Empty when the
  /// line has nothing to say beyond the name.
  final String? serverSubtitle;

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
  /// It lives in core/widgets/terminal_type.dart because the servers tab, the
  /// import steps and this head are one voice: the same face, the same weight
  /// rule, the same tracking. A private copy of it is how two screens end up
  /// set in two different faces.
  TextStyle _mono(
    BuildContext context, {
    required double size,
    required Color color,
    double weight = 600,
    double spacing = 1.1,
  }) {
    return terminalText(
      context,
      size: size,
      color: color,
      weight: weight,
      spacing: spacing,
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
        // No label line.
        //
        // It said «ПОДКЛЮЧЕНИЕ», which is the name of the tab the person is
        // already standing on — the rail and the bottom bar both say it — and
        // it put the word «подключение» three lines above the word
        // «подключено». One screen, one name, one state: the head opens with
        // the node.
        //
        // Where you are, in the middle and large. The mark and the name are
        // twice the old reading: the node is the thing this screen is about.
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The same mark the profile list draws for this node. It was a
              // globe here and a red YouTube tile there, for the same line:
              // one node, one mark, wherever it appears.
              if (tile == PoolTile.flag) ...[
                FlagMark(flag: serverFlag ?? '', width: 76),
                const SizedBox(width: 16),
              ] else ...[
                ServerGlyph(
                  label: PoolServerLabel(
                    title: serverName,
                    subtitle: '',
                    tile: tile,
                    flag: '',
                  ),
                  size: 76,
                ),
                const SizedBox(width: 16),
              ],
              Flexible(
                child: Text(
                  serverName.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _mono(
                    context,
                    size: 42,
                    color: ink,
                    weight: 700,
                    spacing: 1.6,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (serverSubtitle != null && serverSubtitle!.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: Text(
              serverSubtitle!.trim(),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 15,
                height: 1.3,
                color: mute,
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        // The state sits on the traffic label, at the left. It used to be
        // centred under the name, which put «не подключено» in the middle of
        // a screen whose only other reading starts at the left edge. The
        // clock, when there is one, stays at the right of that same line.
        Row(
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
            if (windowsDesktop && uptime != null) ...[
              const Spacer(),
              _uptimeField(context, ink, mute, uptime),
            ],
          ],
        ),
        const SizedBox(height: 8),
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
  final TextStyle Function(BuildContext,
      {required double size,
      required Color color,
      double weight,
      double spacing}) mono;

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
              ? (isHead ? color : color.withValues(alpha: night ? 0.55 : 0.88))
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

/// One imported server, drawn as a plate with a row on it.
///
/// It was a Material tile: a grey slab with a hairline, the scheme in a boxed
/// chip on the left, the host in the default subtitle, and the trash on a
/// square of paper colour. Nothing on it belonged to the same app as the
/// profile cards. This is the row grammar of a pool line, promoted to a plate of
/// its own: the same mark, the same name-over-subtitle stack, the same gold wash
/// for the chosen one and the same ring for the one thing you can do to it.
class ImportedProfileCard extends StatelessWidget {
  const ImportedProfileCard({
    super.key,
    required this.name,
    required this.scheme,
    required this.endpoint,
    required this.selected,
    this.label,
    this.connected = false,
    this.dialable = true,
    this.onTap,
    this.onDelete,
  });

  final String name;
  final String scheme;
  final String endpoint;

  /// The same label the pool lines use, so a pasted key and a node out of a
  /// list are one object drawn once.
  final PoolServerLabel? label;

  final bool selected;
  final bool connected;
  final bool dialable;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final l = AppL10n.of(context);
    final mute = dark ? AppBrand.inkMutedDark : AppBrand.inkMutedLight;
    final gold = dark ? AppBrand.mascotGoldLit : AppBrand.mascotGoldDeep;
    final mark = label ??
        PoolServerLabel(
          title: name,
          subtitle: '',
          tile: PoolTile.flag,
          flag: '',
        );
    final title = label == null || label!.title.isEmpty ? name : label!.title;
    final subtitle = !dialable
        ? l.freeSchemeParked
        : (label != null && label!.subtitle.isNotEmpty
            ? label!.subtitle
            : endpoint);

    return AppSurface(
      clip: true,
      child: HoverBuilder(
        onTap: onTap,
        builder: (context, hover) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            color: selected
                ? gold.withValues(alpha: dark ? 0.13 : 0.10)
                : (hover
                    ? theme.colorScheme.onSurface.withValues(alpha: 0.04)
                    : Colors.transparent),
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
                  padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
                  child: Row(
                    children: [
                      ServerGlyph(label: mark, size: 32),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
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
                                color:
                                    dialable ? mute : theme.colorScheme.error,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      // The lamp, not a tick in a circle: green is the one hue
                      // in the palette that means a thing is working, and this
                      // is the only place on the servers tab that does.
                      if (connected) ...[
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: dark ? AppBrand.mossLight : AppBrand.moss,
                            boxShadow: [
                              BoxShadow(
                                color:
                                    (dark ? AppBrand.mossLight : AppBrand.moss)
                                        .withValues(alpha: 0.45),
                                blurRadius: 8,
                                spreadRadius: -2,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      _schemeTag(context, mute, gold),
                      if (onDelete != null) ...[
                        const SizedBox(width: 6),
                        AppRingButton(
                          icon: AppIcons.trash,
                          color: mute,
                          onPressed: onDelete,
                          tooltip: l.freeDelete,
                          size: 30,
                          iconSize: 15,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// The protocol, in the terminal's voice over a wash of the house gold —
  /// the same tag a node line wears. A parked scheme says so in plain ink
  /// instead: it is not something you can act on here.
  Widget _schemeTag(BuildContext context, Color mute, Color gold) {
    final dial = dialable;
    final ink = dial ? gold : mute;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: dial
            ? AppBrand.mascotGold.withValues(
                alpha: Theme.of(context).brightness == Brightness.dark
                    ? 0.16
                    : 0.13,
              )
            : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        scheme.toUpperCase(),
        style: terminalText(
          context,
          size: 9.5,
          color: ink,
          weight: 700,
          spacing: 1.4,
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
