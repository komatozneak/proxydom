import 'package:flutter/material.dart';

import '../../../core/ios_store_gates.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/app_action_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_surface.dart';
import '../../../l10n/app_localizations.dart';

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
  });

  final VoidCallback onPaste;
  final VoidCallback onScan;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    const barHeight = 54.0;
    const gap = SizedBox(width: 10);
    // Add server is the primary: it is the only thing a person has to do to get
    // this screen to work. Refresh is the quiet one, and on a phone it gets a
    // ring rather than a slab so the two read as one family, not two rivals.
    final add = AppActionButton(
      onPressed: onPaste,
      icon: AppIcons.plus,
      label: l.freeAddServer,
      color: AppBrand.mascotGold,
      height: barHeight,
    );
    final refresh = onRefresh;
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
                color: AppBrand.mascotGoldDeep,
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
            color: AppBrand.mascotGold,
            onPressed: refresh,
            tooltip: l.freeRefresh,
            size: barHeight,
          ),
          gap,
          AppRingButton(
            icon: AppIcons.qrCode,
            color: AppBrand.mascotGold,
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

/// The head of the home screen.
///
/// The status used to be a two-line readout floating in the middle of the
/// screen with nothing above it, which is why it read as a label rather than
/// as the state of anything. A head has a hierarchy: what this screen is,
/// what the tunnel is doing, and the facts behind it.
class ConnectionReadout extends StatelessWidget {
  const ConnectionReadout({
    super.key,
    required this.eyebrow,
    required this.status,
    required this.profile,
    required this.traffic,
    required this.accent,
    this.uptime,
    this.trafficColor,
  });

  /// «Подключение» — the name of the screen, quiet, above everything.
  final String eyebrow;
  final String status;
  final String profile;
  final String traffic;
  final Color accent;
  final String? uptime;
  final Color? trafficColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final mute = dark ? AppBrand.inkMutedDark : AppBrand.inkMutedLight;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: mute,
            fontSize: 11.5,
            letterSpacing: 2.0,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _Lamp(color: accent, size: 14),
            const SizedBox(width: 11),
            Flexible(
              child: Text(
                status,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: accent,
                  fontSize: 25,
                  height: 1.12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
            ),
            if (uptime != null) ...[
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  uptime!,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: mute,
                    fontSize: 15,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        // The facts, on one line, in the order a person asks for them: where,
        // how, how much.
        Text(
          '$profile  ·  $traffic',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (trafficColor != null) const SizedBox.shrink(),
      ],
    );
  }
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
